import 'package:flutter/material.dart';
import 'design.dart';
import 'document_activity.dart';
import 'document_fields.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'widgets.dart';
import 'ui/access_gate.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.api,
    required this.doctype,
    this.name,
    this.company,
    this.initial,
    this.treeParent,
  });
  final ErpApi api;
  final String doctype;
  final String? name, company, treeParent;
  final NativeDocument? initial;
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  final _form = GlobalKey<_NativeDocumentFormState>();
  bool _freshAccess = false;
  late Future<(NativeSchema, NativeDocument)> _future = _load();
  Future<(NativeSchema, NativeDocument)> _load() async {
    final results = await Future.wait([
      widget.api.nativeSchema(widget.doctype),
      widget.initial != null && !_freshAccess
          ? Future.value(widget.initial!)
          : widget.api.nativeDocument(
              widget.doctype,
              name: _freshAccess && _form.currentState != null
                  ? (_form.currentState!._doc.isNew
                        ? null
                        : _form.currentState!._data['name'] as String?)
                  : widget.name,
              company: widget.company,
              treeParent: widget.treeParent,
            ),
    ]);
    return (results[0] as NativeSchema, results[1] as NativeDocument);
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      _freshAccess = true;
      final fresh = _load();
      setState(() {
        _future = fresh;
      });
      await fresh;
    },
    child: FutureBuilder<(NativeSchema, NativeDocument)>(
      future: _future,
      builder: (context, state) {
        if (state.hasData) {
          final (schema, doc) = state.data!;
          return NativeDocumentForm(
            key: _form,
            schema: schema,
            initial: doc,
            onActivity: (values) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DocumentActivityScreen(
                  api: widget.api,
                  type: widget.doctype,
                  name: values['name'] as String,
                ),
              ),
            ),
            onRelated: (values, action) async {
              final created = await widget.api.newFromNative(
                schema.doctype,
                values['name'] as String,
                action,
                values['modified'] as String,
              );
              if (context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentEditor(
                      api: widget.api,
                      doctype: created.data['doctype'] as String,
                      initial: created,
                      company: widget.company,
                    ),
                  ),
                );
              }
            },
            onSave: (values, action) =>
                widget.api.saveNative(schema, values, action: action),
            onPartyDefaults: schema.partyDefaults
                ? (values) => widget.api.partyDefaultsNative(schema, values)
                : null,
            onItemDefaults: schema.itemDefaults
                ? (values, field, row) =>
                      widget.api.itemDefaultsNative(schema, values, field, row)
                : null,
            onPrepare: schema.preparable
                ? (values) => widget.api.prepareNative(schema, values)
                : null,
            onLink: (type, query, field) => widget.api.searchLinks(
              type,
              query,
              parent: schema.doctype,
              field: field.name,
            ),
            onNewRow: (values, field) =>
                widget.api.newRowNative(schema, values, field.name),
            onTransition: (values, action) => widget.api.transitionNative(
              schema.doctype,
              values['name'] as String,
              action,
              modified: values['modified'] as String,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(widget.doctype)),
          body: state.hasError
              ? MessagePanel(
                  title: 'COULD NOT OPEN',
                  message: state.error.toString(),
                  action: () => setState(() {
                    _future = _load();
                  }),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
    ),
  );
}

class NativeDocumentForm extends StatefulWidget {
  const NativeDocumentForm({
    super.key,
    required this.schema,
    required this.initial,
    required this.onSave,
    this.onPrepare,
    this.onPartyDefaults,
    this.onItemDefaults,
    this.onLink,
    this.onNewRow,
    this.onTransition,
    this.onActivity,
    this.onRelated,
  });
  final Future<void> Function(Map<String, dynamic>, String)? onRelated;
  final ValueChanged<Map<String, dynamic>>? onActivity;
  final NativeSchema schema;
  final NativeDocument initial;
  final Future<NativeDocument> Function(
    Map<String, dynamic> values,
    String action,
  )
  onSave;
  final Future<NativeDocument> Function(Map<String, dynamic> values)? onPrepare;
  final Future<NativeDocument> Function(
    Map<String, dynamic> values,
    String action,
  )?
  onTransition;
  final LinkLookup? onLink;
  final RowDefaults? onNewRow;
  final ItemDefaults? onItemDefaults;
  final Future<NativeDocument> Function(Map<String, dynamic>)? onPartyDefaults;
  @override
  State<NativeDocumentForm> createState() => _NativeDocumentFormState();
}

class _NativeDocumentFormState extends State<NativeDocumentForm> {
  late NativeDocument _doc = widget.initial;
  late Map<String, dynamic> _data = _doc.editCopy();
  Map<String, String> _errors = {};
  bool _busy = false, _dirty = false, _leaving = false;
  String? _error, _notice;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant NativeDocumentForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.initial, widget.initial)) {
      final allowed = widget.schema.payload(_data);
      _doc = widget.initial;
      _data = {
        ..._doc.editCopy(),
        if (_dirty && (_doc.can('write') || _doc.can('create')))
          for (final f in widget.schema.fields.where(
            (f) => !f.readOnly && !f.hidden && !f.layout,
          ))
            if (allowed.containsKey(f.name)) f.name: allowed[f.name],
      };
      _errors = {};
      _error = null;
      _revision++;
      _notice =
          'Access refreshed. Review your retained draft and current source values before saving.';
    }
  }

  Future<void> _perform(
    String action, {
    bool prepare = false,
    bool workflow = false,
    bool party = false,
  }) async {
    if (_busy) return;
    if (workflow && _dirty) {
      setState(
        () => _error = 'Save your changes before applying a workflow action.',
      );
      return;
    }
    final errors = widget.schema.validate(_data);
    if (!party && errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _error = 'Check the marked fields before saving.';
      });
      return;
    }
    if (action != 'Save' && !prepare) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$action ${widget.schema.doctype}?'),
          content: const Text(
            'ERPNext will check permissions and apply the business rules for this action.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _errors = {};
      _error = null;
      _notice = null;
    });
    try {
      final result = party
          ? await widget.onPartyDefaults!(_data)
          : prepare
          ? await widget.onPrepare!(_data)
          : workflow
          ? await widget.onTransition!(_data, action)
          : await widget.onSave(_data, action);
      if (!mounted) return;
      setState(() {
        _doc = result;
        _data = result.editCopy();
        _revision++;
        _dirty = prepare || party;
        _notice = party
            ? 'Party details updated'
            : prepare
            ? 'Calculations updated'
            : action == 'Save'
            ? 'Saved successfully'
            : '$action completed';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _related(String action) async {
    if (_busy) return;
    if (_dirty) {
      setState(
        () => _error = 'Save your changes before creating a related document.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRelated!(_data, action);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || _leaving) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _leaving = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keep your changes?'),
        content: const Text('This document has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _doc.data['docstatus'] ?? 0;
    final canSave =
        status != 2 && (_doc.isNew ? _doc.can('create') : _doc.can('write'));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: WorkspaceTheme.canvas,
          title: Display(widget.schema.doctype.toUpperCase(), size: 27),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: _busy || !canSave ? null : () => _perform('Save'),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _doc.isNew
                            ? 'New ${widget.schema.doctype}'
                            : _doc.data['name']?.toString() ??
                                  widget.schema.doctype,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      StatusChip(
                        _dirty
                            ? 'Unsaved changes'
                            : status == 2
                            ? 'Cancelled'
                            : status == 1
                            ? 'Submitted'
                            : _doc.isNew
                            ? 'New'
                            : 'Draft',
                      ),
                      if (widget.onRelated != null &&
                          _doc.relatedActions.isNotEmpty)
                        PopupMenuButton<String>(
                          enabled: !_busy,
                          onSelected: _related,
                          itemBuilder: (_) => [
                            for (final action in _doc.relatedActions)
                              PopupMenuItem(value: action, child: Text(action)),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Create / copy ▾'),
                          ),
                        ),
                      if (!_doc.isNew && widget.onActivity != null)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => widget.onActivity!(_data),
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('Files & activity'),
                        ),
                      if (widget.onPartyDefaults != null &&
                          canSave &&
                          status == 0)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _perform('Save', party: true),
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Load party details'),
                        ),
                      if (widget.onPrepare != null && canSave && status == 0)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _perform('Save', prepare: true),
                          icon: const Icon(Icons.calculate_outlined, size: 18),
                          label: const Text('Update calculations'),
                        ),
                      if (widget.schema.submittable &&
                          status == 0 &&
                          !_doc.isNew &&
                          _doc.can('submit') &&
                          _doc.workflow.isEmpty)
                        TextButton(
                          onPressed: _busy ? null : () => _perform('Submit'),
                          child: const Text('Submit'),
                        ),
                      if (status == 1 &&
                          _doc.can('cancel') &&
                          _doc.workflow.isEmpty)
                        TextButton(
                          onPressed: _busy ? null : () => _perform('Cancel'),
                          child: const Text('Cancel document'),
                        ),
                      if (widget.onTransition != null)
                        for (final transition in _doc.transitions)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _perform(
                                    transition['action'] as String,
                                    workflow: true,
                                  ),
                            child: Text(transition['action'] as String),
                          ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: WorkspaceTheme.ink,
                          height: 1.5,
                        ),
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _notice!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Panel(
                    border: true,
                    child: DocumentFields(
                      key: ValueKey(_revision),
                      schema: widget.schema,
                      data: _data,
                      errors: _errors,
                      editable: !_busy && canSave,
                      onLink: widget.onLink,
                      onNewRow: widget.onNewRow,
                      onItemDefaults: widget.onItemDefaults,
                      onChanged: () => setState(() {
                        _dirty = true;
                        _notice = null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
