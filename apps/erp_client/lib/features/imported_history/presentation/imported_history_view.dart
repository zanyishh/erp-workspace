import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../models/history_filter_intent.dart';
import 'history_filter_text.dart';
import 'history_register_view_model.dart';

String _text(Object? value) => value?.toString() ?? '';
String _date(Object? value) =>
    _text(value).isEmpty ? 'Not recorded' : _text(value);
const _productionColumns = <(String, String)>[
  ('original_date', 'Date'),
  ('shift', 'Shift'),
  ('job', 'Job order'),
  ('party', 'Customer'),
  ('description', 'Fabric'),
  ('dia', 'Dia / size'),
  ('machine', 'Machine'),
  ('operator', 'Operator'),
  ('rolls', 'Rolls / PCS'),
  ('net_kg', 'Production kg'),
  ('native_id', 'Original ID'),
];

class ImportedHistoryView extends StatefulWidget {
  const ImportedHistoryView({
    super.key,
    required this.model,
    required this.company,
    required this.editFilters,
    required this.openRecord,
    required this.openProduction,
    required this.protect,
  });
  final HistoryRegisterViewModel model;
  final String company;
  final Future<Map<String, dynamic>?> Function(HistoryFilterIntent) editFilters;
  final void Function(String) openRecord;
  final void Function(Map<String, dynamic>) openProduction;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<ImportedHistoryView> createState() => _ImportedHistoryViewState();
}

class _ImportedHistoryViewState extends State<ImportedHistoryView> {
  late final search = TextEditingController(text: widget.model.query);
  Timer? debounce;
  List<Map<String, dynamic>> get families => widget.model.families;
  List<Map<String, dynamic>> get rows => widget.model.rows;
  List<Map<String, dynamic>> get cashBalances => widget.model.cashBalances;
  String? get family => widget.model.family;
  String? get error => widget.model.error;
  Map<String, dynamic> get filters => widget.model.filters;
  Map<String, String> get filterLabels => widget.model.filterLabels;
  int? get rowCount => widget.model.rowCount;
  int get start => widget.model.start;
  bool get loading => widget.model.loading;
  bool get hasMore => widget.model.hasMore;
  bool get sharedAvailable => widget.model.sharedAvailable;
  @override
  void didUpdateWidget(covariant ImportedHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      debounce?.cancel();
      search.text = widget.model.query;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() {
    debounce?.cancel();
    return widget.model.loadSummary();
  }

  Future<void> _revalidate() {
    debounce?.cancel();
    search.clear();
    return widget.model.revalidate();
  }

  void _choose(String? value) {
    debounce?.cancel();
    search.clear();
    widget.model.chooseFamily(value);
  }

  void _search(String value) {
    debounce?.cancel();
    final model = widget.model, scope = model.scope;
    model.beginSearch();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted && identical(model, widget.model) && model.isCurrent(scope)) {
        model.search(value);
      }
    });
  }

  Future<void> _editFilters() async {
    final model = widget.model, intent = widget.model.prepareFilters();
    if (intent == null) return;
    final result = await widget.editFilters(intent);
    if (mounted && identical(model, widget.model) && result != null) {
      await model.applyFilters(intent, result);
    }
  }

  void _openProduction() {
    if (widget.model.canReadProduction) widget.openProduction(filters);
  }

  void _openRecord(Map<String, dynamic> row) {
    final name = row['name'] as String;
    if (widget.model.canOpen(name)) widget.openRecord(name);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => widget.protect(
      Scaffold(
        appBar: AppBar(
          title: const Text('Imported history'),
          actions: [
            IconButton(
              tooltip: 'Refresh history',
              onPressed: _loadSummary,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.company,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Original records · Read-only',
                  style: TextStyle(color: WorkspaceTheme.muted),
                ),
                const SizedBox(height: 16),
                if (families.isNotEmpty || sharedAvailable)
                  DropdownButtonFormField<String>(
                    key: ValueKey(family),
                    initialValue: family,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Records'),
                    items: [
                      for (final item in families)
                        DropdownMenuItem(
                          value: _text(item['key']),
                          child: Text(
                            '${_text(item['label'])} · ${item['count']} total',
                          ),
                        ),
                      if (sharedAvailable)
                        const DropdownMenuItem(
                          value: 'shared_cash',
                          child: Text('Shared cash'),
                        ),
                    ],
                    onChanged: _choose,
                  ),
                const SizedBox(height: 12),
                if (family == 'shared_cash')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Shared across companies',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (family != null)
                  TextField(
                    controller: search,
                    onChanged: _search,
                    decoration: const InputDecoration(
                      labelText: 'Search original references',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                const SizedBox(height: 12),
                if (family != null)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: loading ? null : _editFilters,
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: const Text('Filter records'),
                      ),
                      if (family == 'production' &&
                          widget.model.canReadProduction)
                        OutlinedButton.icon(
                          onPressed: loading ? null : _openProduction,
                          icon: const Icon(Icons.summarize_outlined),
                          label: const Text('Original production reports'),
                        ),
                      if (filters.isNotEmpty)
                        TextButton(
                          onPressed: loading ? null : widget.model.clearFilters,
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                if (filters.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Applied: ${historyFilterSummary(filters, labels: filterLabels)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading original records',
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(error!),
                        TextButton(
                          onPressed: _loadSummary,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child:
                      !loading &&
                          error == null &&
                          rows.isEmpty &&
                          family != 'shared_cash'
                      ? const Center(child: Text('No records in this view.'))
                      : family == 'production' &&
                            rows.isNotEmpty &&
                            rows.every((row) => row['production_fields'] is Map)
                      ? _productionTable()
                      : ListView.separated(
                          itemCount:
                              rows.length +
                              (family == 'shared_cash' &&
                                      !loading &&
                                      error == null
                                  ? 1
                                  : 0),
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            if (family == 'shared_cash' &&
                                !loading &&
                                error == null) {
                              if (index == 0) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _cashControls(),
                                    if (rows.isEmpty)
                                      const Text('No records in this view.'),
                                  ],
                                );
                              }
                              index--;
                            }
                            final row = rows[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              title: Text(_text(row['title'])),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_text(row['reference'])} · ${_date(row['original_date'])}',
                                  ),
                                  if (_text(row['summary']).isNotEmpty)
                                    Text(_text(row['summary'])),
                                  if (_text(row['review_status']).isNotEmpty)
                                    Text(
                                      _text(row['review_status']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openRecord(row),
                            );
                          },
                        ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      rows.isEmpty
                          ? (rowCount == null
                                ? '0 records shown'
                                : '0 of $rowCount matching records')
                          : '${start + 1}–${start + rows.length}${rowCount == null ? '' : ' of $rowCount'}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: loading || start == 0
                              ? null
                              : widget.model.previousPage,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Previous'),
                        ),
                        OutlinedButton.icon(
                          onPressed: loading || !hasMore
                              ? null
                              : widget.model.nextPage,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      _revalidate,
    ),
  );
  Widget _productionTable() => SingleChildScrollView(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        horizontalMargin: 8,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 76,
        columns: [
          for (final column in _productionColumns)
            DataColumn(
              label: Text(column.$2),
              numeric: column.$1 == 'rolls' || column.$1 == 'net_kg',
            ),
          const DataColumn(label: Text('Record')),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final column in _productionColumns)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        _date(
                          column.$1 == 'original_date' ||
                                  column.$1 == 'native_id'
                              ? row[column.$1]
                              : column.$1 == 'job' &&
                                    _text(row['job_reference_display'])
                                        .isNotEmpty
                              ? row['job_reference_display']
                              : (row['production_fields'] as Map)[column.$1],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                DataCell(
                  IconButton(
                    tooltip:
                        'View original production ${_text(row['native_id'])}',
                    onPressed: () => _openRecord(row),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _cashControls() {
    if (cashBalances.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Source balances are not available yet.'),
      );
    }
    const columns = <(String, String)>[
      ('label', 'Shared book'),
      ('opening_net', 'Opening net'),
      ('movement_debit', 'Movement debit'),
      ('movement_credit', 'Movement credit'),
      ('net', 'Source net'),
      ('verified', 'Control'),
      ('as_of_date', 'As of'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Full shared-book controls · Unaffected by display filters. Source net preserves debit less credit across all companies.',
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (final column in columns)
                      DataColumn(label: Text(column.$2)),
                  ],
                  rows: [
                    for (final row in cashBalances)
                      DataRow(
                        cells: [
                          for (final column in columns)
                            DataCell(
                              Text(
                                column.$1 == 'verified'
                                    ? (row['verified'] == true
                                          ? 'Source matched'
                                          : 'Needs review')
                                    : _text(row[column.$1]).isEmpty
                                    ? 'Not recorded'
                                    : _text(row[column.$1]),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
