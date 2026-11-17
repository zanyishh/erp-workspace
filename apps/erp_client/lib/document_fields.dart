import 'formatted_text.dart';
import 'document_lookup.dart';
import 'document_dialogs.dart';
import 'ui/workspace_ui.dart';
import 'ui/access_gate.dart';
import 'ui/record_icon.dart';
import 'ui/workspace_art.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'design.dart';
import 'native_models.dart';
import 'native_barcode.dart';
import 'specialized_fields.dart';
import 'location_field.dart';
import 'widgets.dart';

typedef LinkLookup = Future<List<Map<String, dynamic>>> Function(
  String type,
  String query,
  NativeField field,
);
typedef RowDefaults = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> parent,
  NativeField field,
);

typedef ItemDefaults = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> parent,
  NativeField field,
  Map<String, dynamic> row,
);

class DocumentFields extends StatefulWidget {
  const DocumentFields({
    super.key,
    required this.schema,
    required this.data,
    required this.onChanged,
    this.errors = const {},
    this.editable = true,
    this.onLink,
    this.onNewRow,
    this.onItemDefaults,
    this.openFieldFile,
    this.parentTable,
    this.parent = const {},
    this.scopeKey,
  });
  final NativeSchema schema;
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final Map<String, String> errors;
  final bool editable;
  final LinkLookup? onLink;
  final RowDefaults? onNewRow;
  final ItemDefaults? onItemDefaults;
  final OpenFieldFile? openFieldFile;
  final String? parentTable;
  final Map<String, dynamic> parent;
  final Object? scopeKey;

  @override
  DocumentFieldsState createState() => DocumentFieldsState();
}

class DocumentFieldsState extends State<DocumentFields> {
  bool _tableBusy = false;
  final _expanded = <String, bool>{};
  final _anchors = <String, GlobalKey>{};
  final _focusNodes = <String, FocusNode>{};
  final _fieldSections = <String, String>{};
  DialogRoute<Map<String, dynamic>>? _rowRoute;
  late Object _rowContext = (
    widget.scopeKey,
    widget.data['company'],
    widget.parent['company'],
  );

  GlobalKey _anchor(String name) =>
      _anchors.putIfAbsent(name, () => GlobalKey());
  FocusNode _focus(String name) =>
      _focusNodes.putIfAbsent(name, () => FocusNode(debugLabel: name));

  @override
  void dispose() {
    dismissDocumentDialog(_rowRoute);
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(DocumentFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextContext = (
      widget.scopeKey,
      widget.data['company'],
      widget.parent['company'],
    );
    final changedContext = _rowContext != nextContext;
    _rowContext = nextContext;
    if (!identical(oldWidget.data, widget.data) ||
        changedContext ||
        !widget.editable) {
      dismissDocumentDialog(_rowRoute);
    }
  }

  Future<void> revealError(String path, {bool openRow = false}) async {
    final parts = path.split('.');
    final name = parts.first;
    setState(() {
      final section = _fieldSections[name];
      if (section != null) _expanded[section] = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = parts.length > 1 ? '$name.${parts[1]}' : name;
    final anchor = _anchors[target]?.currentContext;
    if (anchor != null && anchor.mounted) {
      await Scrollable.ensureVisible(
        anchor,
        alignment: .2,
        duration: workspaceMotion(context),
      );
      if (!mounted) return;
      _focusNodes[target]?.requestFocus();
    }
    if (openRow && parts.length > 2) {
      final field = widget.schema.fields
          .where((f) => f.name == name)
          .firstOrNull;
      final index = int.tryParse(parts[1]);
      if (field != null && index != null) {
        await _row(field, index, parts.skip(2).join('.'));
      }
    }
  }

  bool _canEdit(NativeField field) =>
      widget.editable &&
      !field.locked(widget.data, widget.parent) &&
      (widget.data['docstatus'] == null ||
          widget.data['docstatus'] == 0 ||
          widget.data['docstatus'] == 1 && field.allowOnSubmit);

  int _rowIndex(List rows, Object original) {
    final name = objectMap(original)['name'];
    return rows.indexWhere(
      (row) =>
          identical(row, original) ||
          name != null && name.toString().isNotEmpty && row['name'] == name,
    );
  }

  Future<void> _row(NativeField field, [int? index, String? errorField]) async {
    if (_tableBusy) return;
    final document = widget.data;
    final scope = _rowContext;
    final rows = document[field.name] as List? ?? [];
    final child = widget.schema.children[field.options];
    if (child == null) return;
    final original = index == null ? null : rows[index];
    final canEdit = _canEdit(field);
    setState(() => _tableBusy = true);
    try {
      final route = DialogRoute<Map<String, dynamic>>(
        context: context,
        builder: (_) => _NativeRowDialog(
          schema: child,
          field: field,
          parent: document,
          initial: original == null ? null : objectMap(original),
          index: index,
          editable: canEdit,
          onLink: widget.onLink,
          openFieldFile: widget.openFieldFile,
          onNewRow: widget.onNewRow,
          onItemDefaults: widget.onItemDefaults,
          initialErrors: {
            for (final entry in widget.errors.entries)
              if (index != null &&
                  entry.key.startsWith('${field.name}.$index.'))
                entry.key.substring('${field.name}.$index.'.length): entry.value
                    .replaceFirst('Row ${index + 1}: ', ''),
          },
          errorField: errorField,
          scopeKey: widget.scopeKey,
        ),
      );
      _rowRoute = route;
      final values = await Navigator.of(context).push(route);
      _rowRoute = null;
      if (values == null ||
          !mounted ||
          !identical(widget.data, document) ||
          (widget.scopeKey, widget.data['company'], widget.parent['company']) !=
              scope ||
          !canEdit ||
          !_canEdit(field)) {
        return;
      }
      final updated = [...(document[field.name] as List? ?? [])];
      if (original == null) {
        updated.add(values);
      } else {
        final currentIndex = _rowIndex(updated, original);
        if (currentIndex < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This row was removed while it was open. Changes were not applied.',
              ),
            ),
          );
          return;
        }
        updated[currentIndex] = values;
      }
      document[field.name] = updated;
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _tableBusy = false);
    }
  }

  void _remove(NativeField field, Object row) {
    if (_tableBusy || !_canEdit(field)) return;
    final rows = [...(widget.data[field.name] as List? ?? [])];
    final index = _rowIndex(rows, row);
    if (index < 0) return;
    final document = widget.data;
    final company = document['company'];
    final scope = widget.scopeKey;
    final removed = rows.removeAt(index);
    final following = index < rows.length ? rows[index] : null;
    document[field.name] = rows;
    widget.onChanged();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${field.label}: row ${index + 1} removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted ||
                !identical(widget.data, document) ||
                document['company'] != company ||
                widget.scopeKey != scope ||
                !_canEdit(field)) {
              return;
            }
            final latest = [...(document[field.name] as List? ?? [])];
            if (_rowIndex(latest, removed) >= 0) return;
            final next = following == null ? -1 : _rowIndex(latest, following);
            latest.insert(
              next >= 0 ? next : index.clamp(0, latest.length),
              removed,
            );
            document[field.name] = latest;
            widget.onChanged();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final sections =
          <({String key, String label, List<NativeField> fields})>[];
      var key = '';
      var label = '';
      var fields = <NativeField>[];
      void finish() {
        if (fields.isNotEmpty) {
          sections.add((key: key, label: label, fields: fields));
        }
        fields = [];
      }

      for (final field in widget.schema.visibleFields(
        widget.data,
        parent: widget.parent,
      )) {
        if (const {
              'Section Break',
              'Tab Break',
              'Heading',
            }.contains(field.type) &&
            field.label.isNotEmpty &&
            field.label != field.name) {
          finish();
          key = field.name;
          label = field.label;
        } else {
          fields.add(field);
          _fieldSections[field.name] = key;
        }
      }
      finish();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sections.any((section) => section.label.isNotEmpty))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  for (final section in sections) {
                    _expanded[section.key] = true;
                  }
                }),
                child: const Text('Show all sections'),
              ),
            ),
          for (final section in sections)
            Builder(
              builder: (_) {
                final mustOpen = section.fields.any(
                  (field) =>
                      !field.layout &&
                      (field.mandatory(widget.data, widget.parent) ||
                          widget.errors.keys.any(
                            (error) =>
                                error == field.name ||
                                error.startsWith('${field.name}.'),
                          )),
                );
                final populated = section.fields.any((field) {
                  final value = widget.data[field.name];
                  return !field.layout &&
                      value != null &&
                      value != '' &&
                      (value is! List || value.isNotEmpty);
                });
                final expanded =
                    section.label.isEmpty ||
                    mustOpen ||
                    _expanded.putIfAbsent(
                      section.key,
                      () => populated || section == sections.first,
                    );
                return Column(
                  key: ValueKey(section.key),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section.label.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(sectionSymbol(section.label), size: 20),
                        title: Text(
                          section.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: mustOpen
                            ? const Text('Required fields or corrections')
                            : null,
                        trailing: mustOpen
                            ? null
                            : Icon(
                                expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                        onTap: mustOpen
                            ? null
                            : () => setState(
                                () => _expanded[section.key] = !expanded,
                              ),
                      ),
                    Offstage(
                      offstage: !expanded,
                      child: ExcludeFocus(
                        excluding: !expanded,
                        child: TickerMode(
                          enabled: expanded,
                          child: _buildSection(section.fields, box),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      );
    },
  );

  Widget _buildSection(List<NativeField> fields, BoxConstraints box) {
    final widgets = <Widget>[];
    final group = <NativeField>[];
    void flush() {
      if (group.isEmpty) return;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final width = box.maxWidth >= 780 * scale.clamp(1.0, 2.0)
          ? (box.maxWidth - 20) / 2
          : box.maxWidth;
      widgets.add(
        Wrap(
          spacing: 20,
          runSpacing: 18,
          children: [
            for (final field in group)
              SizedBox(
                key: _anchor(field.name),
                width:
                    const {
                      'Text',
                      'Long Text',
                      'Small Text',
                      'Text Editor',
                      'HTML Editor',
                      'Markdown Editor',
                      'Code',
                      'JSON',
                      'Geolocation',
                      'Signature',
                    }.contains(field.type)
                    ? box.maxWidth
                    : width,
                child: NativeScalarField(
                  focusNode: _focus(field.name),
                  scopeKey: (
                    widget.scopeKey,
                    widget.data['company'],
                    widget.data['name'],
                    widget.parent['company'],
                  ),
                  key: ValueKey(field.name),
                  field: field,
                  openFile: widget.openFieldFile == null
                      ? null
                      : () => widget.openFieldFile!(
                          context,
                          field.name,
                          widget.parentTable,
                          widget.parentTable == null
                              ? null
                              : widget.data['name']?.toString(),
                        ),
                  value: widget.data[field.name],
                  error: widget.errors[field.name],
                  required: field.mandatory(widget.data, widget.parent),
                  editable:
                      widget.editable &&
                      !field.locked(widget.data, widget.parent) &&
                      (!enabled(widget.data['docstatus']) ||
                          field.allowOnSubmit),
                  linkType:
                      field.type == 'Dynamic Link' ||
                          field.multiple &&
                              widget.schema.fields.any(
                                (f) => f.name == field.options,
                              )
                      ? widget.data[field.options]?.toString() ?? ''
                      : field.options,
                  onLink: widget.onLink,
                  onChanged: (value) {
                    widget.data[field.name] = value;
                    if (field.type == 'Barcode') {
                      final companion = barcodeCompanion(field.options);
                      for (final other in widget.schema.fields.where(
                        (f) => f.name == companion && f.type == 'Data',
                      )) {
                        if (_canEdit(other)) widget.data[other.name] = value;
                      }
                    }
                    widget.onChanged();
                  },
                ),
              ),
          ],
        ),
      );
      group.clear();
    }

    for (final field in fields) {
      if (field.layout) {
        if (const {
          'Section Break',
          'Tab Break',
          'Heading',
        }.contains(field.type)) {
          flush();
          if (field.label.isNotEmpty && field.label != field.name) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 14),
                child: Row(
                  children: [
                    Icon(sectionSymbol(field.label), size: 19),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Display(field.label.toUpperCase(), size: 24),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        continue;
      }
      if (field.table) {
        flush();
        final rows = widget.data[field.name] as List? ?? [];
        final child = widget.schema.children[field.options];
        final canEdit = _canEdit(field);
        widgets.add(
          Padding(
            key: _anchor(field.name),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Panel(
              border: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            RecordIcon(recordSymbol(field.options), size: 30),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Display(
                                '${field.label.toUpperCase()} · ${rows.length}',
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canEdit)
                        TextButton.icon(
                          focusNode: _focus(field.name),
                          onPressed: _tableBusy ? null : () => _row(field),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add row'),
                        ),
                    ],
                  ),
                  if (widget.errors[field.name] != null)
                    Text(
                      widget.errors[field.name]!,
                      style: const TextStyle(color: WorkspaceTheme.muted),
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('No rows yet.'),
                    ),
                  for (var i = 0; i < rows.length; i++)
                    ListTile(
                      key: _anchor('${field.name}.$i'),
                      focusNode: _focus('${field.name}.$i'),
                      contentPadding: EdgeInsets.zero,
                      leading: Text('${i + 1}'),
                      title: Text(
                        child == null
                            ? 'Row ${i + 1}'
                            : child.fields
                                  .where(
                                    (f) => !f.layout && !f.hidden && !f.table,
                                  )
                                  .map((f) => rows[i][f.name]?.toString() ?? '')
                                  .where((v) => v.isNotEmpty)
                                  .take(3)
                                  .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: _rowErrors(field, i),
                      onTap: _tableBusy ? null : () => _row(field, i),
                      trailing: canEdit
                          ? IconButton(
                              tooltip: 'Remove row ${i + 1}',
                              onPressed: _tableBusy
                                  ? null
                                  : () => _remove(field, rows[i]),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 19,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        );
      } else {
        group.add(field);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget? _rowErrors(NativeField field, int index) {
    final errors = widget.errors.entries
        .where((entry) => entry.key.startsWith('${field.name}.$index.'))
        .map((entry) => entry.value);
    return errors.isEmpty
        ? null
        : Text(
            errors.join('\n'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
  }
}

class _NativeRowDialog extends StatefulWidget {
  const _NativeRowDialog({
    required this.schema,
    required this.field,
    required this.parent,
    required this.initial,
    required this.index,
    required this.editable,
    this.onLink,
    this.onNewRow,
    this.onItemDefaults,
    this.openFieldFile,
    this.initialErrors = const {},
    this.errorField,
    this.scopeKey,
  });
  final Map<String, String> initialErrors;
  final String? errorField;
  final Object? scopeKey;
  final OpenFieldFile? openFieldFile;
  final NativeSchema schema;
  final NativeField field;
  final Map<String, dynamic> parent;
  final Map<String, dynamic>? initial;
  final int? index;
  final bool editable;
  final LinkLookup? onLink;
  final RowDefaults? onNewRow;
  final ItemDefaults? onItemDefaults;

  @override
  State<_NativeRowDialog> createState() => _NativeRowDialogState();
}

class _NativeRowDialogState extends State<_NativeRowDialog> {
  final _fieldsKey = GlobalKey<DocumentFieldsState>();
  DialogRoute<bool>? _leaveRoute;
  @override
  void dispose() {
    dismissDocumentDialog(_leaveRoute);
    super.dispose();
  }

  late Map<String, dynamic> _values;
  late String _initialValues;
  bool _busy = false;
  bool _leaving = false;
  bool _initialLoadFailed = false;
  String? _loadError;
  Map<String, String> _errors = {};

  bool get _dirty => widget.editable && jsonEncode(_values) != _initialValues;

  @override
  void initState() {
    super.initState();
    _values = widget.initial == null
        ? {
            'doctype': widget.schema.doctype,
            '__islocal': 1,
            for (final field in widget.schema.fields)
              if (field.defaultValue != null) field.name: field.defaultValue,
          }
        : objectMap(jsonDecode(jsonEncode(widget.initial)));
    _initialValues = jsonEncode(_values);
    _errors = widget.initialErrors;
    if (widget.errorField != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fieldsKey.currentState?.revealError(widget.errorField!),
      );
    }
    if (widget.initial == null && widget.onNewRow != null) {
      _loadNewRow();
    }
  }

  Future<void> _loadNewRow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _initialLoadFailed = false;
      _loadError = null;
    });
    try {
      final values = await widget.onNewRow!(widget.parent, widget.field);
      if (mounted) {
        setState(() {
          _values = objectMap(jsonDecode(jsonEncode(values)));
          _initialValues = jsonEncode(_values);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialLoadFailed = true;
          _loadError = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadItem() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final values = await widget.onItemDefaults!(
        widget.parent,
        widget.field,
        objectMap(jsonDecode(jsonEncode(_values))),
      );
      if (mounted) setState(() => _values = values);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
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
    final route = DialogRoute<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keep your changes?'),
        content: const Text('This row has unsaved changes.'),
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
    _leaveRoute = route;
    final discard = await Navigator.of(context).push(route);
    _leaveRoute = null;
    _leaving = false;
    if (discard == true && mounted) Navigator.pop(context);
  }

  void _done() {
    if (_busy || _initialLoadFailed) return;
    if (!widget.editable) {
      Navigator.pop(context);
      return;
    }
    final errors = widget.schema.validate(_values, parent: widget.parent);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _fieldsKey.currentState?.revealError(errors.keys.first);
      return;
    }
    Navigator.pop(context, _values);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.field.label} · ${widget.index == null ? 'New row' : 'Row ${widget.index! + 1}'}',
          ),
          leading: IconButton(
            tooltip: 'Close row',
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (widget.editable &&
                widget.onItemDefaults != null &&
                widget.schema.fields.any((field) => field.name == 'item_code'))
              TextButton(
                onPressed: _busy || _initialLoadFailed ? null : _loadItem,
                child: const Text('Load item details'),
              ),
            TextButton(
              onPressed: _busy || _initialLoadFailed ? null : _done,
              child: Text(widget.editable ? 'Done' : 'Close'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_loadError!)),
                      ],
                    ),
                  ),
                ),
              if (_initialLoadFailed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loadNewRow,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry loading row'),
                  ),
                ),
              if (_errors.isNotEmpty)
                DocumentErrorSummary(
                  errors: _errors,
                  onSelect: (path) =>
                      _fieldsKey.currentState?.revealError(path, openRow: true),
                ),
              DocumentFields(
                key: _fieldsKey,
                scopeKey: widget.scopeKey,
                schema: widget.schema,
                parent: widget.parent,
                openFieldFile: widget.openFieldFile,
                parentTable: widget.field.name,
                data: _values,
                errors: _errors,
                editable: widget.editable && !_busy && !_initialLoadFailed,
                onLink: widget.onLink,
                onChanged: () => setState(() {
                  if (_errors.isNotEmpty) {
                    _errors = widget.schema.validate(
                      _values,
                      parent: widget.parent,
                    );
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class NativeScalarField extends StatefulWidget {
  const NativeScalarField({
    super.key,
    required this.field,
    required this.value,
    required this.editable,
    required this.onChanged,
    this.onCommitted,
    this.error,
    this.onLink,
    this.openFile,
    this.linkType = '',
    this.required,
    this.focusNode,
    this.scopeKey,
  });
  final Future<void> Function()? openFile;
  final NativeField field;
  final Object? value;
  final bool editable;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onCommitted;
  final String? error;
  final String linkType;
  final bool? required;
  final FocusNode? focusNode;
  final Object? scopeKey;
  final LinkLookup? onLink;
  @override
  State<NativeScalarField> createState() => _NativeScalarFieldState();
}

class _NativeScalarFieldState extends State<NativeScalarField> {
  DialogRoute<String>? _linkRoute;
  ModalRoute<dynamic>? _pickerRoute;
  AccessScope? _accessScope;
  Object get _scope => (widget.scopeKey, _accessScope?.identity);
  bool get _canInteract => widget.editable && (_accessScope?.isCurrent ?? true);

  void _dismissDialogs() {
    for (final route in [_linkRoute, _pickerRoute]) {
      dismissDocumentDialog(route);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessScope = AccessScope.maybeOf(context);
    if (_accessScope?.identity != accessScope?.identity) _dismissDialogs();
    _accessScope = accessScope;
  }

  late final TextEditingController _text = TextEditingController(
    text: _displayValue(),
  );
  String _displayValue() {
    if (widget.value is Map || widget.field.type == 'Signature') return '';
    final value = widget.value?.toString() ?? '';
    return widget.field.type == 'Barcode' ? barcodeText(value) : value;
  }

  @override
  void didUpdateWidget(NativeScalarField old) {
    super.didUpdateWidget(old);
    if (old.linkType != widget.linkType ||
        old.scopeKey != widget.scopeKey ||
        !widget.editable) {
      _dismissDialogs();
    }
    final value = _displayValue();
    if (value != _text.text) {
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _dismissDialogs();
    _text.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (_linkRoute != null ||
        widget.onLink == null ||
        widget.linkType.isEmpty ||
        !_canInteract) {
      return;
    }
    final type = widget.linkType;
    final scope = _scope;
    final lookup = widget.onLink!;
    final field = widget.field;
    final route = DialogRoute<String>(
      context: context,
      builder: (_) => DocumentLinkSearch(
        label: field.multiple ? field.label : type,
        search: (query) => lookup(type, query, field),
      ),
    );
    _linkRoute = route;
    final value = await Navigator.of(context).push(route);
    _linkRoute = null;
    if (value == null ||
        !mounted ||
        !_canInteract ||
        widget.linkType != type ||
        _scope != scope) {
      return;
    }
    if (field.multiple) {
      final values = List<String>.from(widget.value as List? ?? []);
      if (!values.contains(value)) widget.onChanged([...values, value]);
    } else {
      widget.onChanged(value);
      widget.onCommitted?.call();
    }
  }

  String _dateText(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  void _picked(String value) {
    _text.text = value;
    widget.onChanged(value);
  }

  Future<void> _chooseDate() async {
    if (!_canInteract || _pickerRoute != null) return;
    final scope = _scope;
    final previous = _text.text.trim();
    final parsed = DateTime.tryParse(previous) ?? DateTime.now();
    final first = DateTime(1800);
    final last = DateTime(2200, 12, 31);
    final picked = await showDatePicker(
      context: context,
      builder: (dialog, child) {
        _pickerRoute = ModalRoute.of(dialog);
        return child!;
      },
      initialDate: parsed.isBefore(first)
          ? first
          : parsed.isAfter(last)
          ? last
          : parsed,
      firstDate: first,
      lastDate: last,
    );
    _pickerRoute = null;
    if (picked == null || !mounted || !_canInteract || _scope != scope) {
      return;
    }
    final time =
        RegExp(r'^\d{4}-\d{2}-\d{2}[T ](.+)$').firstMatch(previous)?.group(1) ??
        '00:00:00';
    _picked(
      '${_dateText(picked)}${widget.field.type == 'Datetime' ? ' $time' : ''}',
    );
  }

  Future<void> _chooseTime() async {
    if (!_canInteract || _pickerRoute != null) return;
    final scope = _scope;
    final datetime = widget.field.type == 'Datetime';
    final parsed =
        DateTime.tryParse(datetime ? _text.text : '2000-01-01 ${_text.text}') ??
        DateTime.now();
    final picked = await showTimePicker(
      context: context,
      builder: (dialog, child) {
        _pickerRoute = ModalRoute.of(dialog);
        return child!;
      },
      initialTime: TimeOfDay.fromDateTime(parsed),
    );
    _pickerRoute = null;
    if (picked == null || !mounted || !_canInteract || _scope != scope) {
      return;
    }
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    _picked('${datetime ? '${_dateText(parsed)} ' : ''}$time');
  }

  Widget _focusGroup(Widget child) => widget.focusNode == null
      ? child
      : Focus(focusNode: widget.focusNode, child: child);

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final label =
        '${field.label}${widget.required ?? field.required ? ' *' : ''}';
    if (field.type == 'Attach' || field.type == 'Attach Image') {
      return _focusGroup(
        PrivateFileField(
          label: label,
          value: widget.value,
          error: widget.error,
          image: field.type == 'Attach Image',
          editable: widget.editable,
          onChanged: widget.onChanged,
          open: widget.openFile,
        ),
      );
    }
    if (field.type == 'Text Editor') {
      return _focusGroup(
        FormattedTextField(
          label: label,
          value: widget.value?.toString() ?? '',
          editable: widget.editable,
          error: widget.error,
          onChanged: widget.onChanged,
        ),
      );
    }
    if (field.type == 'Geolocation') {
      return _focusGroup(
        LocationField(
          label: label,
          value: widget.value,
          editable: widget.editable,
          error: widget.error,
          onChanged: widget.onChanged,
        ),
      );
    }
    if (field.type == 'Signature') {
      return _focusGroup(
        SignatureField(
          label: label,
          value: widget.value?.toString(),
          error: widget.error,
          editable: widget.editable,
          onChanged: widget.onChanged,
        ),
      );
    }
    if (field.type == 'Barcode' ||
        field.type == 'Data' &&
            {'barcode', 'scan_barcode'}.contains(field.name)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            focusNode: widget.focusNode,
            controller: _text,
            readOnly: !widget.editable,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: label,
              errorText: widget.error,
              prefixIcon: const Icon(Icons.qr_code_2),
              hintText: widget.editable ? 'Scan or type a code' : null,
            ),
            onChanged: widget.editable
                ? (value) {
                    widget.onChanged(value);
                    setState(() {});
                  }
                : null,
          ),
          BarcodePreview(
            value: _text.text,
            options: field.type == 'Barcode' ? field.options : '',
          ),
        ],
      );
    }
    if (field.multiple) {
      final values = List<String>.from(widget.value as List? ?? []);
      return InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: widget.error),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final value in values)
              InputChip(
                label: Text(value),
                onDeleted: widget.editable
                    ? () => widget.onChanged([...values]..remove(value))
                    : null,
              ),
            if (widget.editable)
              IconButton(
                tooltip: 'Find ${field.label}',
                onPressed: widget.linkType.isEmpty ? null : _link,
                icon: const Icon(Icons.add_circle_outline, size: 21),
              ),
            if (values.isEmpty && !widget.editable) const Text('—'),
          ],
        ),
      );
    }
    if (field.type == 'Check') {
      return CheckboxListTile(
        focusNode: widget.focusNode,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: enabled(widget.value),
        onChanged: widget.editable
            ? (value) => widget.onChanged(value == true ? 1 : 0)
            : null,
      );
    }
    if (field.type == 'Select' && field.options.isNotEmpty && widget.editable) {
      final choices = {'', ...field.options.split('\n')}.toList();
      final value = widget.value?.toString() ?? '';
      if (!choices.contains(value)) choices.add(value);
      return DropdownButtonFormField<String>(
        focusNode: widget.focusNode,
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, errorText: widget.error),
        items: [
          for (final choice in choices)
            DropdownMenuItem(
              value: choice,
              child: Text(
                choice.isEmpty ? '—' : choice,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: widget.onChanged,
      );
    }
    final multiline = const {
      'Small Text',
      'Text',
      'Long Text',
      'Text Editor',
      'HTML Editor',
      'Markdown Editor',
      'Code',
      'JSON',
      'Geolocation',
    }.contains(field.type);
    final linked = field.type == 'Link' || field.type == 'Dynamic Link';
    final date = field.type == 'Date' || field.type == 'Datetime';
    return TextFormField(
      focusNode: widget.focusNode,
      controller: _text,
      onEditingComplete: _canInteract ? widget.onCommitted : null,
      readOnly: !widget.editable,
      obscureText: field.type == 'Password',
      autocorrect: !linked && field.type != 'Password' && !field.numeric,
      enableSuggestions: field.type != 'Password',
      textAlign: field.numeric ? TextAlign.end : TextAlign.start,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.next,
      maxLines: multiline ? 4 : 1,
      keyboardType: field.numeric
          ? TextInputType.numberWithOptions(
              decimal: field.type != 'Int',
              signed: true,
            )
          : date || field.type == 'Time'
          ? TextInputType.datetime
          : multiline
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        errorText: widget.error,
        suffixIcon: !widget.editable
            ? const Icon(Icons.lock_outline, size: 16)
            : linked
            ? IconButton(
                tooltip: 'Find ${field.label}',
                onPressed: widget.linkType.isEmpty ? null : _link,
                icon: const Icon(Icons.search, size: 19),
              )
            : date || field.type == 'Time'
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (date)
                    IconButton(
                      tooltip: 'Choose ${field.label}',
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                  if (field.type == 'Time' || field.type == 'Datetime')
                    IconButton(
                      tooltip: 'Choose ${field.label}${date ? ' time' : ''}',
                      onPressed: _chooseTime,
                      icon: const Icon(Icons.schedule, size: 18),
                    ),
                ],
              )
            : null,
      ),
      onChanged: widget.editable ? widget.onChanged : null,
    );
  }
}

class DocumentErrorSummary extends StatelessWidget {
  const DocumentErrorSummary({
    super.key,
    required this.errors,
    required this.onSelect,
  });
  final Map<String, String> errors;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Review ${errors.length} ${errors.length == 1 ? 'field' : 'fields'}',
              ),
            ),
          ],
        ),
        for (final entry in errors.entries)
          TextButton(
            onPressed: () => onSelect(entry.key),
            child: Text('Go to correction: ${entry.value}'),
          ),
      ],
    ),
  );
}
