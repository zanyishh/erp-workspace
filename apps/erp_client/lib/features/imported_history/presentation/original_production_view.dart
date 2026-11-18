import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../models/history_filter_intent.dart';
import 'history_filter_text.dart';
import 'original_production_view_model.dart';

class OriginalProductionView extends StatefulWidget {
  const OriginalProductionView({
    super.key,
    required this.model,
    required this.company,
    required this.editFilters,
    required this.openHistory,
    required this.protect,
  });
  final OriginalProductionViewModel model;
  final String company;
  final Future<Map<String, dynamic>?> Function(HistoryFilterIntent) editFilters;
  final void Function(Map<String, dynamic>) openHistory;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<OriginalProductionView> createState() => _OriginalProductionViewState();
}

class _OriginalProductionViewState extends State<OriginalProductionView> {
  String get group => widget.model.group;
  Map<String, dynamic> get filters => widget.model.filters;
  Map<String, String> get filterLabels => widget.model.filterLabels;
  List<Map<String, dynamic>> get rows => widget.model.rows;
  Map<String, dynamic>? get totals => widget.model.totals;
  String? get error => widget.model.error;
  int get start => widget.model.start;
  int get rowCount => widget.model.rowCount;
  bool get loading => widget.model.loading;
  bool get hasMore => widget.model.hasMore;
  bool get allowed => widget.model.allowed;
  Future<void> _load() => widget.model.reload();
  Future<void> _revalidate() => widget.model.revalidate();
  Future<void> _editFilters() async {
    final model = widget.model, intent = widget.model.prepareFilters();
    if (intent == null) return;
    final result = await widget.editFilters(intent);
    if (mounted && identical(model, widget.model) && result != null) {
      await model.applyFilters(intent, result);
    }
  }

  void _open(Map<String, dynamic> row) {
    if (!loading && widget.model.canDrill(row)) {
      widget.openHistory(Map<String, dynamic>.from(row['filters'] as Map));
    }
  }

  String _quantity(Object? value) => value?.toString() ?? 'Unrecorded';

  Widget _summary() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            for (final (key, label) in [
              ('source_record_count', 'Original records'),
              ('quantity_kg', 'Recorded production kg'),
              ('recorded_count', 'Recorded rolls / PCS'),
            ])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: WorkspaceTheme.muted),
                  ),
                  SelectableText(
                    _quantity(totals![key]),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${totals!['missing_quantity_rows']} records without kg · ${totals!['missing_count_rows']} records without rolls / PCS',
        ),
      ],
    ),
  );

  Widget _table() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowHeight: null,
      dataRowMinHeight: 56,
      dataRowMaxHeight: double.infinity,
      columnSpacing: 24,
      columns: [
        DataColumn(label: Text(originalProductionGroups[group]!)),
        const DataColumn(label: Text('Records'), numeric: true),
        const DataColumn(label: Text('Recorded kg'), numeric: true),
        const DataColumn(label: Text('Recorded rolls / PCS'), numeric: true),
        const DataColumn(label: Text('Without kg'), numeric: true),
        const DataColumn(label: Text('Without rolls / PCS'), numeric: true),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(
                row['drillable'] == true
                    ? TextButton(
                        onPressed: () => _open(row),
                        child: Text(row['label'] as String),
                      )
                    : Text(row['label'] as String),
              ),
              for (final key in [
                'source_record_count',
                'quantity_kg',
                'recorded_count',
                'missing_quantity_rows',
                'missing_count_rows',
              ])
                DataCell(SelectableText(_quantity(row[key]))),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => widget.protect(
      Scaffold(
        appBar: AppBar(title: const Text('Original production')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.company,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Original production · Read-only',
                style: TextStyle(color: WorkspaceTheme.muted),
              ),
              const SizedBox(height: 12),
              const Text(
                'Exact sums of recorded kg and rolls / PCS. Missing values are counted separately. Identical saved labels are grouped together; labels do not establish employee identity or valuation.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: const ValueKey('original-production-group'),
                initialValue: group,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Group originals by',
                ),
                items: [
                  for (final entry in originalProductionGroups.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: loading
                    ? null
                    : (value) {
                        if (value == null || value == group) return;
                        widget.model.chooseGroup(value);
                      },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: loading || error != null ? null : _editFilters,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Filter records'),
                  ),
                  if (filters.isNotEmpty)
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              widget.model.clearFilters();
                            },
                      child: const Text('Clear filters'),
                    ),
                  IconButton(
                    tooltip: 'Refresh report',
                    onPressed: loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (filters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Applied: ${historyFilterSummary(filters, labels: filterLabels)}',
                  ),
                ),
              const SizedBox(height: 16),
              if (loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading original production report',
                ),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ),
              ],
              if (totals != null) ...[
                _summary(),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const Text('No original production in this view.')
                else
                  _table(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      rows.isEmpty
                          ? '0 of $rowCount groups'
                          : '${start + 1}–${start + rows.length} of $rowCount groups',
                    ),
                    OutlinedButton(
                      onPressed: start == 0 || loading
                          ? null
                          : () {
                              widget.model.previousPage();
                            },
                      child: const Text('Previous groups'),
                    ),
                    OutlinedButton(
                      onPressed: !hasMore || loading
                          ? null
                          : () {
                              widget.model.nextPage();
                            },
                      child: const Text('Next groups'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      _revalidate,
    ),
  );
}
