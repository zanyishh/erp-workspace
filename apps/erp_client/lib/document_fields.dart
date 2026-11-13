import 'ui/record_icon.dart';
import 'ui/workspace_art.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'design.dart';
import 'native_models.dart';
import 'widgets.dart';

typedef LinkLookup =
    Future<List<Map<String, dynamic>>> Function(
      String type,
      String query,
      NativeField field,
    );
typedef RowDefaults =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> parent,
      NativeField field,
    );

typedef ItemDefaults =
    Future<Map<String, dynamic>> Function(
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
    this.parent = const {},
  });
  final NativeSchema schema;
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final Map<String, String> errors;
  final bool editable;
  final LinkLookup? onLink;
  final RowDefaults? onNewRow;
  final ItemDefaults? onItemDefaults;
  final Map<String, dynamic> parent;

  @override
  State<DocumentFields> createState() => _DocumentFieldsState();
}

class _DocumentFieldsState extends State<DocumentFields> {
  bool _tableBusy = false;

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

  Future<void> _row(NativeField field, [int? index]) async {
    if (_tableBusy) return;
    final document = widget.data;
    final rows = document[field.name] as List? ?? [];
    final child = widget.schema.children[field.options];
    if (child == null) return;
    final original = index == null ? null : rows[index];
    final canEdit = _canEdit(field);
    setState(() => _tableBusy = true);
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _NativeRowDialog(
          schema: child,
          field: field,
          parent: document,
          initial: original == null ? null : objectMap(original),
          index: index,
          editable: canEdit,
          onLink: widget.onLink,
          onNewRow: widget.onNewRow,
          onItemDefaults: widget.onItemDefaults,
        ),
      );
      if (values == null ||
          !mounted ||
          !identical(widget.data, document) ||
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
    widget.data[field.name] = rows..removeAt(index);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final widgets = <Widget>[];
      final group = <NativeField>[];
      void flush() {
        if (group.isEmpty) return;
        final width = box.maxWidth >= 780
            ? (box.maxWidth - 20) / 2
            : box.maxWidth;
        widgets.add(
          Wrap(
            spacing: 20,
            runSpacing: 18,
            children: [
              for (final field in group)
                SizedBox(
                  width: width,
                  child: NativeScalarField(
                    key: ValueKey(field.name),
                    field: field,
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
                      widget.onChanged();
                    },
                  ),
                ),
            ],
          ),
        );
        group.clear();
      }

      for (final field in widget.schema.visibleFields(
        widget.data,
        parent: widget.parent,
      )) {
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
                        contentPadding: EdgeInsets.zero,
                        leading: Text('${i + 1}'),
                        title: Text(
                          child == null
                              ? 'Row ${i + 1}'
                              : child.fields
                                    .where(
                                      (f) => !f.layout && !f.hidden && !f.table,
                                    )
                                    .map(
                                      (f) => rows[i][f.name]?.toString() ?? '',
                                    )
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
    },
  );

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
  });
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
    final discard = await showDialog<bool>(
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
                  child: Text(_loadError!),
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
              DocumentFields(
                schema: widget.schema,
                parent: widget.parent,
                data: _values,
                errors: _errors,
                editable: widget.editable && !_busy && !_initialLoadFailed,
                onLink: widget.onLink,
                onChanged: () => setState(() {}),
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
    this.error,
    this.onLink,
    this.linkType = '',
    this.required,
  });
  final NativeField field;
  final Object? value;
  final bool editable;
  final ValueChanged<Object?> onChanged;
  final String? error;
  final String linkType;
  final bool? required;
  final LinkLookup? onLink;
  @override
  State<NativeScalarField> createState() => _NativeScalarFieldState();
}

class _NativeScalarFieldState extends State<NativeScalarField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value?.toString() ?? '',
  );
  @override
  void didUpdateWidget(NativeScalarField old) {
    super.didUpdateWidget(old);
    final value = widget.value?.toString() ?? '';
    if (value != _text.text) {
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (widget.onLink == null || widget.linkType.isEmpty) return;
    var future = widget.onLink!(widget.linkType, '', widget.field);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (c, update) => Dialog(
          child: SizedBox(
            width: 520,
            height: 480,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Display(
                          'CHOOSE ${widget.linkType.toUpperCase()}',
                          size: 25,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close search',
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search records…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (query) => update(() {
                      future = widget.onLink!(
                        widget.linkType,
                        query,
                        widget.field,
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: future,
                      builder: (context, state) {
                        if (state.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (state.hasError) {
                          return SingleChildScrollView(
                            child: Text(state.error.toString()),
                          );
                        }
                        final rows = state.data ?? [];
                        if (rows.isEmpty) {
                          return const Center(
                            child: Text('No matching records.'),
                          );
                        }
                        return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) => ListTile(
                            title: Text(rows[i]['value']?.toString() ?? ''),
                            subtitle: Text(
                              (rows[i]['description'] ?? rows[i]['label'] ?? '')
                                  .toString()
                                  .replaceAll(RegExp(r'<[^>]*>'), ''),
                            ),
                            onTap: () =>
                                Navigator.pop(c, rows[i]['value']?.toString()),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      if (widget.field.multiple) {
        final values = List<String>.from(widget.value as List? ?? []);
        if (!values.contains(value)) widget.onChanged([...values, value]);
      } else {
        widget.onChanged(value);
      }
    }
  }

  String _dateText(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  void _picked(String value) {
    _text.text = value;
    widget.onChanged(value);
  }

  Future<void> _chooseDate() async {
    final previous = _text.text.trim();
    final parsed = DateTime.tryParse(previous) ?? DateTime.now();
    final first = DateTime(1800);
    final last = DateTime(2200, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed.isBefore(first)
          ? first
          : parsed.isAfter(last)
          ? last
          : parsed,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    final time =
        RegExp(r'^\d{4}-\d{2}-\d{2}[T ](.+)$').firstMatch(previous)?.group(1) ??
        '00:00:00';
    _picked(
      '${_dateText(picked)}${widget.field.type == 'Datetime' ? ' $time' : ''}',
    );
  }

  Future<void> _chooseTime() async {
    final datetime = widget.field.type == 'Datetime';
    final parsed =
        DateTime.tryParse(datetime ? _text.text : '2000-01-01 ${_text.text}') ??
        DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(parsed),
    );
    if (picked == null || !mounted) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    _picked('${datetime ? '${_dateText(parsed)} ' : ''}$time');
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final label =
        '${field.label}${widget.required ?? field.required ? ' *' : ''}';
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
      controller: _text,
      readOnly: !widget.editable,
      obscureText: field.type == 'Password',
      maxLines: multiline ? 4 : 1,
      keyboardType: field.numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
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
