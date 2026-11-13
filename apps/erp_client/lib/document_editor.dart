import 'ui/record_icon.dart';
import 'ui/workspace_ui.dart';
import 'dart:convert';
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
    this.onCreated,
  });
  final ErpApi api;
  final String doctype;
  final String? name, company, treeParent;
  final NativeDocument? initial;
  final ValueChanged<NativeDocument>? onCreated;
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  var _form = GlobalKey<_NativeDocumentFormState>();
  bool _freshAccess = false;
  late Future<(NativeSchema, NativeDocument)> _future = _load();
  Future<NativeDocument> _document() {
    final current = _form.currentState?._doc ?? widget.initial;
    if (!_freshAccess && widget.initial != null) {
      return Future.value(widget.initial!);
    }
    final origin = current?.data['__native_origin'];
    if (current?.isNew == true && origin is Map) {
      return widget.api.newFromNative(
        origin['doctype'] as String,
        origin['name'] as String,
        origin['action'] as String,
        origin['modified'] as String,
      );
    }
    return widget.api.nativeDocument(
      widget.doctype,
      name: current == null
          ? widget.name
          : current.isNew
          ? null
          : current.data['name'] as String?,
      company: widget.company,
      treeParent: widget.treeParent,
    );
  }

  Future<(NativeSchema, NativeDocument)> _load() async {
    final results = await Future.wait([
      widget.api.nativeSchema(widget.doctype),
      _document(),
    ]);
    return (results[0] as NativeSchema, results[1] as NativeDocument);
  }

  Future<void> _reloadLatest() async {
    _freshAccess = true;
    final revision = widget.api.accessRevision;
    final fresh = _load();
    await fresh;
    if (!mounted || revision != widget.api.accessRevision) return;
    setState(() {
      _form = GlobalKey<_NativeDocumentFormState>();
      _future = fresh;
    });
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      _freshAccess = true;
      final revision = widget.api.accessRevision;
      final fresh = _load();
      await fresh;
      if (mounted && widget.api.accessRevision == revision) {
        setState(() {
          _future = fresh;
        });
      }
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
            onReload: _reloadLatest,
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
                // The linked voucher may have settled or fulfilled this record.
                if (mounted) await _reloadLatest();
              }
            },
            onSave: (values, action) async {
              final saved = await widget.api.saveNative(
                schema,
                values,
                action: action,
              );
              if (mounted &&
                  widget.onCreated != null &&
                  !saved.isNew &&
                  (values['name'] == null || enabled(values['__islocal']))) {
                widget.onCreated!(saved);
              }
              return saved;
            },
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
    this.onReload,
  });
  final Future<void> Function()? onReload;
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
  late Map<String, dynamic> _base;

  Map<String, String> _errors = {};
  bool _busy = false, _dirty = false, _leaving = false;
  String? _error, _notice;
  bool _stale = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _base = widget.initial.data;
  }

  @override
  void didUpdateWidget(covariant NativeDocumentForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.initial, widget.initial)) {
      _doc = widget.initial;
      final fresh = _doc.editCopy();
      if (_dirty &&
          _doc.can(_doc.isNew ? 'create' : 'write') &&
          fresh['docstatus'] != 2) {
        _retainDraft(widget.schema, _base, _data, fresh);
      }
      _data = fresh;
      _base = _doc.data;
      _dirty = jsonEncode(fresh) != jsonEncode(_base);
      _errors = {};
      _stale = false;
      _error = null;
      _revision++;
      _notice = _dirty
          ? 'Access refreshed. Review your retained edits before saving.'
          : 'Access refreshed. Showing current values.';
    }
  }

  // Reapply only edits still allowed by the fresh schema. A draft can contain
  // partially typed numbers, so parsing belongs to validation and save.
  void _retainDraft(
    NativeSchema schema,
    Map<String, dynamic> base,
    Map<String, dynamic> draft,
    Map<String, dynamic> fresh, {
    Map<String, dynamic> parent = const {},
  }) {
    final status = (parent.isEmpty ? fresh : parent)['docstatus'];
    for (final field in schema.visibleFields(fresh, parent: parent)) {
      final key = field.name;
      if (field.layout ||
          field.locked(fresh, parent) ||
          status == 1 && !field.allowOnSubmit ||
          !draft.containsKey(key) ||
          jsonEncode(draft[key]) == jsonEncode(base[key])) {
        continue;
      }
      if (!field.table) {
        fresh[key] = draft[key];
        continue;
      }
      final child = schema.children[field.options];
      if (child == null) continue;
      final previous = [for (final r in base[key] as List? ?? []) objectMap(r)];
      final current = [for (final r in fresh[key] as List? ?? []) objectMap(r)];
      final oldByName = {
        for (final r in previous)
          if (r['name'] != null) r['name']: r,
      };
      final currentByName = {
        for (final r in current)
          if (r['name'] != null) r['name']: r,
      };
      final rows = <Map<String, dynamic>>[];
      for (final (i, value) in (draft[key] as List? ?? []).indexed) {
        final row = objectMap(value);
        final name = row['name'];
        final old = name != null
            ? oldByName[name]
            : i < previous.length && previous[i]['name'] == null
            ? previous[i]
            : null;
        final now = name != null
            ? currentByName[name]
            : i < current.length && current[i]['name'] == null
            ? current[i]
            : null;
        if (old != null && now == null) continue;
        final target =
            now ?? {'doctype': child.doctype, '__islocal': 1, 'name': ?name};
        _retainDraft(child, old ?? {}, row, target, parent: fresh);
        rows.add(target);
      }
      fresh[key] = [
        ...rows,
        for (final row in current)
          if (row['name'] != null &&
              !oldByName.containsKey(row['name']) &&
              !rows.contains(row))
            row,
      ];
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
          content: Text(switch (action) {
            'Submit' =>
              'Submit ${_doc.data['name']}? Changes after submission may require a cancellation or amendment.',
            'Cancel' =>
              'Cancel ${_doc.data['name']} and reverse its postings? Linked documents can prevent cancellation.',
            _ => 'Apply "$action" to ${_doc.data['name']}?',
          }),
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
        _stale = false;
        _data = result.editCopy();
        _revision++;
        _dirty = prepare || party;
        if (!_dirty) _base = result.data;
        _notice = party
            ? 'Party details updated'
            : prepare
            ? 'Calculations updated'
            : action == 'Save'
            ? 'Saved successfully'
            : '$action completed';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _stale = e is ErpException && e.staleDocument;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadConflict() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reload the latest version?'),
          content: const Text(
            'Your unsaved edits will be replaced by the current server values.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard and reload'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.onReload!();
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
          title: Row(
            children: [
              RecordHeaderMark(
                widget.schema.doctype,
                settings: widget.schema.single,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.schema.doctype,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: _busy || !canSave ? null : () => _perform('Save'),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: WorkspaceTheme.light,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: WorkspaceBackdrop(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_data['company'] is String &&
                          (_data['company'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _data['company'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
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
                            style: displayStyle(32),
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
                                : widget.schema.submittable
                                ? 'Draft'
                                : 'Saved',
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.onRelated != null &&
                              _doc.relatedActions.isNotEmpty)
                            PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: _related,
                              itemBuilder: (_) => [
                                for (final action in _doc.relatedActions)
                                  PopupMenuItem(
                                    value: action,
                                    child: Text(action),
                                  ),
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
                          if (widget.onPrepare != null &&
                              canSave &&
                              status == 0)
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _perform('Save', prepare: true),
                              icon: const Icon(
                                Icons.calculate_outlined,
                                size: 18,
                              ),
                              label: const Text('Update calculations'),
                            ),
                          if (widget.schema.submittable &&
                              status == 0 &&
                              !_doc.isNew &&
                              _doc.can('submit') &&
                              _doc.workflow.isEmpty)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _perform('Submit'),
                              child: const Text('Submit'),
                            ),
                          if (status == 1 &&
                              _doc.can('cancel') &&
                              _doc.workflow.isEmpty)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _perform('Cancel'),
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
                          child: Semantics(
                            liveRegion: true,
                            child: Row(
                              children: [
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(_revision),
                                  tween: Tween(
                                    begin:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? 1.0
                                        : .55,
                                    end: 1,
                                  ),
                                  curve: Curves.easeOutCubic,
                                  duration: workspaceMotion(context),
                                  builder: (_, scale, child) => Transform.scale(
                                    scale: scale,
                                    child: child,
                                  ),
                                  child: Icon(
                                    _dirty
                                        ? Icons.info_outline
                                        : Icons.check_circle_outline,
                                    size: 21,
                                    color: _dirty
                                        ? WorkspaceTheme.ink
                                        : const Color(0xFF2E634F),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _notice!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_stale && !_doc.isNew && widget.onReload != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _reloadConflict,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload latest version'),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Panel(
                        frosted: true,
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
                            if (_errors.isNotEmpty) {
                              _errors = widget.schema.validate(_data);
                              if (_errors.isEmpty) _error = null;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
