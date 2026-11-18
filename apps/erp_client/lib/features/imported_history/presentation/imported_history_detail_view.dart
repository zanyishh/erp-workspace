import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';

import '../models/history_models.dart';
import 'history_detail_view_model.dart';

String _text(Object? value) => value?.toString() ?? '';
String _date(Object? value) =>
    _text(value).isEmpty ? 'Not recorded' : _text(value);
List<Map<String, dynamic>> _objects(Object? value) =>
    (value as List).cast<Map<String, dynamic>>();

class ImportedHistoryDetailView extends StatefulWidget {
  const ImportedHistoryDetailView({
    super.key,
    required this.model,
    required this.openTarget,
    required this.openRecord,
    required this.openInvoice,
    required this.protect,
  });
  final HistoryDetailViewModel model;
  final void Function(String, String) openTarget;
  final VoidCallback openRecord;
  final void Function(String) openInvoice;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<ImportedHistoryDetailView> createState() =>
      _ImportedHistoryDetailViewState();
}

class _ImportedHistoryDetailViewState extends State<ImportedHistoryDetailView> {
  bool _current(HistoryDetailViewModel model, Object scope) =>
      identical(model, widget.model) && model.isCurrent(scope) && model.ready;
  Future<void> _refresh() async {
    final next = widget.model.reload();
    setState(() {});
    await next;
  }

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: AppBar(title: const Text('Original record')),
      body: FutureBuilder<HistoryDetail>(
        key: ValueKey(widget.model.scope),
        future: widget.model.result,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.error.toString()),
                    TextButton(
                      onPressed: () => _refresh().catchError((_) {}),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!widget.model.ready) {
            return const Center(child: CircularProgressIndicator());
          }
          final model = widget.model, scope = model.scope;
          final data = state.requireData.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _text(data['title']),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SelectableText(_text(data['reference'])),
                const SizedBox(height: 12),
                const Text(
                  'Original records are preserved and cannot be edited here.',
                ),
                const SizedBox(height: 16),
                _field('Original date', _date(data['original_date'])),
                if (_text(data['effective_date']).isNotEmpty &&
                    data['effective_date'] != data['original_date'])
                  _field('Effective date', data['effective_date']),
                if (_text(data['review_status']).isNotEmpty)
                  _field('Review status', data['review_status']),
                for (final note in data['review_notes'] as List)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(note as String)),
                      ],
                    ),
                  ),
                for (final field in _objects(data['fields']))
                  _field(field['label'] as String, field['value']),
                for (final table in _objects(data['tables'])) ...[
                  const SizedBox(height: 20),
                  Text(
                    table['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_objects(table['columns']).isEmpty)
                    Text(
                      _objects(table['rows']).isEmpty
                          ? 'No original lines recorded.'
                          : 'No visible fields in ${_objects(table['rows']).length} original ${_objects(table['rows']).length == 1 ? 'line' : 'lines'}.',
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          for (final c in _objects(table['columns']))
                            DataColumn(label: Text(c['label'] as String)),
                        ],
                        rows: [
                          for (final row in _objects(table['rows']))
                            DataRow(
                              cells: [
                                for (final c in _objects(table['columns']))
                                  DataCell(
                                    SelectableText(_text(row[c['key']])),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
                if (_objects(data['target_links'] ?? []).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Related ERP records',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final link in _objects(data['target_links']))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_text(link['name'])),
                      subtitle: Text(_text(link['doctype'])),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () {
                        if (_current(model, scope)) {
                          widget.openTarget(
                            link['doctype'] as String,
                            link['name'] as String,
                          );
                        }
                      },
                    ),
                ],
                if (data['record_printable'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print original record'),
                        onPressed: () {
                          if (_current(model, scope)) widget.openRecord();
                        },
                      ),
                    ),
                  ),
                if (data['printable'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print original invoice'),
                        onPressed: () {
                          if (_current(model, scope)) {
                            widget.openInvoice(_text(data['reference']));
                          }
                        },
                      ),
                    ),
                  )
                else if (_text(data['print_reason']).isNotEmpty &&
                    data['family'] == 'invoice')
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_text(data['print_reason'])),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    _refresh,
  );
  Widget _field(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 12),
        ),
        SelectableText(_text(value).isEmpty ? 'Not recorded' : _text(value)),
      ],
    ),
  );
}
