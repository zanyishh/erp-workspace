import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/native_models.dart';
import '../../../core/ui/design.dart';
import '../../../core/ui/record_icon.dart';
import '../../../core/ui/retained_load.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/ui/workspace_art.dart';
import '../models/native_reports.dart';
import '../models/report_definition.dart';
import 'report_chart.dart';
import 'report_view_model.dart';

class NativeReportView extends StatefulWidget {
  const NativeReportView({
    super.key,
    required this.model,
    required this.name,
    required this.filterFields,
    required this.open,
    required this.exportFile,
    required this.protect,
  });
  final ReportViewModel model;
  final String name;
  final Widget Function(
    NativeSchema,
    Map<String, dynamic>,
    Map<String, String>,
    VoidCallback,
  )
  filterFields;
  final void Function(String, String) open;
  final Future<void> Function(AppliedReport) exportFile;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<NativeReportView> createState() => _NativeReportViewState();
}

class _NativeReportViewState extends State<NativeReportView> {
  Future<ReportDefinition> get _definition => widget.model.definition;
  Future<AppliedReport>? get _result => widget.model.result;
  Map<String, dynamic>? get _values => widget.model.values;
  Map<String, String> get _errors => widget.model.errors;
  bool get _busy => widget.model.busy;
  bool get _queued => widget.model.queued;
  String? get _error => widget.model.problem;
  void _run() => setState(widget.model.run);
  void _runFilters(Map<String, dynamic> filters) =>
      setState(() => widget.model.runFilters(filters));
  Future<void> _queue(Map<String, dynamic> filters) async {
    final model = widget.model;
    final work = model.queue(filters);
    setState(() {});
    await work;
    if (mounted && identical(model, widget.model)) setState(() {});
  }

  Future<void> _revalidate() async {
    final work = widget.model.revalidate();
    if (mounted) setState(() {});
    await work;
  }

  String _appliedSummary(NativeSchema schema, Map<String, dynamic> filters) {
    if (filters.isEmpty) return 'Applied filters: All records';
    final labels = {for (final field in schema.fields) field.name: field.label};
    return 'Applied filters: ${filters.entries.map((entry) => '${labels[entry.key] ?? entry.key}: ${entry.value is List ? (entry.value as List).join(', ') : entry.value}').join(' · ')}';
  }

  Widget _prepared(Map<String, dynamic> filters) => MessagePanel(
    title: _queued ? 'REPORT IS BEING PREPARED' : 'PREPARED REPORT',
    message: _queued
        ? 'Your report is running in the background. Refresh to check its results.'
        : 'Generate this report in the background, then refresh to view the results.',
    label: _queued ? 'Refresh results' : 'Generate report',
    action: _busy
        ? null
        : _queued
        ? () => _runFilters(filters)
        : () => _queue(filters),
  );

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: _appBar(),
      body: FutureBuilder<ReportDefinition>(
        key: ValueKey(widget.model.scope),
        future: _definition,
        builder: (context, state) {
          if (state.hasError) {
            return MessagePanel(
              title: 'COULD NOT OPEN REPORT',
              message: state.error.toString(),
              action: () => setState(() {
                widget.model.reloadDefinition();
              }),
            );
          }
          if (!state.hasData || widget.model.values == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final definition = state.data!;
          final schema = definition.schema;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _filterPanel(context, schema),
                const SizedBox(height: 18),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                if (_result == null)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                      'Choose your filters, then run the report.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  _results(definition, schema),
              ],
            ),
          );
        },
      ),
    ),
    _revalidate,
  );
  Widget _exports(
    BuildContext context,
    ReportDefinition definition,
    AppliedReport applied,
  ) {
    final report = applied.report;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Display(
          '${report.rows.length} ${report.rows.length == 1 ? 'row' : 'rows'}',
          size: 25,
        ),
        if (definition.canExport && report.columns.isNotEmpty)
          TextButton.icon(
            onPressed: !widget.model.canExport(applied)
                ? null
                : () async {
                    try {
                      await widget.exportFile(applied);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Export CSV'),
          ),
        if (definition.canExport && report.columns.isNotEmpty)
          TextButton.icon(
            onPressed: !widget.model.canExport(applied)
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.model.csv(applied)),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CSV copied for your spreadsheet.'),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy CSV'),
          ),
      ],
    );
  }

  Widget _completed(
    BuildContext context,
    ReportDefinition definition,
    NativeSchema schema,
    RetainedLoad<AppliedReport> result,
    AppliedReport applied,
  ) {
    final report = applied.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RetainedLoadNotice(
          loading: result.loading,
          error: result.error,
          onRetry: () => _run(),
        ),
        if (applied.preparedFilters != null)
          _prepared(applied.preparedFilters!),
        Text(_appliedSummary(schema, applied.filters)),
        if (widget.model.filtersChanged(applied.filters))
          const Text(
            'Filters changed — run to update. Exports use the displayed results.',
          ),
        _exports(context, definition, applied),
        if (report.truncated)
          const Text(
            'Showing the first 10,000 rows. Narrow your filters for a complete view.',
          ),
        if (report.summary.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in report.summary)
                SizedBox(
                  width: 200,
                  child: MetricTile(
                    label: plainReportText(item['label']),
                    value: plainReportText(item['value']),
                    footer: item['currency']?.toString() ?? '',
                  ),
                ),
            ],
          ),
        if (report.chart case final chart?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ReportChart(chart: chart),
          ),
        const SizedBox(height: 12),
        report.rows.isEmpty
            ? const Panel(
                border: true,
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'No rows match these filters.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : report.columns.isEmpty
            ? const Panel(
                border: true,
                child: Text('This report has no visible columns.'),
              )
            : NativeReportTable(
                result: report,
                onDocument: (type, name) {
                  if (widget.model.canUse(applied)) {
                    widget.open(type, name);
                  }
                },
              ),
      ],
    );
  }

  Widget _results(ReportDefinition definition, NativeSchema schema) =>
      RetainedFutureBuilder<AppliedReport>(
        future: _result,
        scope: widget.model.scope,
        builder: (context, result) {
          if (result.loading && !result.hasData) {
            return const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (result.hasError && !result.hasData) {
            return MessagePanel(
              title: 'REPORT COULD NOT RUN',
              message: result.error.toString(),
              action: () => _run(),
            );
          }
          final applied = result.data!;
          final report = applied.report;
          if (report.pending) return _prepared(applied.filters);
          return _completed(context, definition, schema, result, applied);
        },
      );
  Widget _filterPanel(BuildContext context, NativeSchema schema) => Panel(
    border: true,
    child: ExpansionTile(
      expansionAnimationStyle: workspaceReduceMotion(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            ),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      title: const Display('Report filters', size: 25),
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        widget.filterFields(
          schema,
          _values!,
          _errors,
          () => setState(widget.model.changed),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _run(),
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Run report'),
          ),
        ),
      ],
    ),
  );
  PreferredSizeWidget _appBar() => AppBar(
    title: WorkspaceRouteTitle(
      widget.name,
      mark: RecordIcon(recordSymbol(widget.name, report: true)),
    ),
  );
}

class NativeReportTable extends StatelessWidget {
  const NativeReportTable({
    super.key,
    required this.result,
    required this.onDocument,
  });
  final NativeReportResult result;
  final void Function(String doctype, String name) onDocument;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return _CompactReportRows(
          key: ObjectKey(result),
          result: result,
          onDocument: onDocument,
        );
      }
      return PaginatedDataTable(
        key: ObjectKey(result),
        showCheckboxColumn: false,
        showEmptyRows: false,
        rowsPerPage: math.max(1, math.min(25, result.rows.length)),
        availableRowsPerPage: const [25],
        horizontalMargin: 16,
        columnSpacing: 20,
        headingRowHeight: 48,
        columns: [
          for (final col in result.columns)
            DataColumn(
              numeric: _numericColumn(col),
              label: SizedBox(
                width: 140,
                child: ColumnCaption(
                  plainReportText(col.label),
                  fieldtype: col.type,
                  alignEnd: _numericColumn(col),
                ),
              ),
            ),
        ],
        source: _ReportRows(result, onDocument),
      );
    },
  );
}

bool _numericColumn(NativeReportColumn col) => const {
  'Currency',
  'Int',
  'Float',
  'Percent',
  'Duration',
}.contains(col.type);

class _ReportRows extends DataTableSource {
  _ReportRows(this.result, this.onDocument);
  final NativeReportResult result;
  final void Function(String, String) onDocument;
  @override
  int get rowCount => result.rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
  @override
  DataRow? getRow(int index) {
    if (index >= rowCount) return null;
    final row = result.rows[index];
    return DataRow.byIndex(
      index: index,
      cells: [for (final col in result.columns) _cell(col, row)],
    );
  }

  DataCell _cell(NativeReportColumn col, Map<String, dynamic> row) {
    final value = row[col.fieldname];
    final target = _documentType(col, row);
    return DataCell(
      SizedBox(
        width: 140,
        child: Text(
          plainReportText(value),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: _numericColumn(col) ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 13,
            color: WorkspaceTheme.ink,
            decoration: target != null ? TextDecoration.underline : null,
          ),
        ),
      ),
      onTap: target == null ? null : () => onDocument(target, value.toString()),
    );
  }
}

String? _documentType(NativeReportColumn col, Map<String, dynamic> row) {
  final value = row[col.fieldname];
  if ((value is! String && value is! num) ||
      value.toString().isEmpty ||
      value.toString().startsWith('<')) {
    return null;
  }
  final type = switch (col.type) {
    'Dynamic Link' => row[col.options]?.toString(),
    'Link' => col.options,
    _ => null,
  };
  return type == null || type.isEmpty ? null : type;
}

class _CompactReportRows extends StatefulWidget {
  const _CompactReportRows({
    super.key,
    required this.result,
    required this.onDocument,
  });
  final NativeReportResult result;
  final void Function(String, String) onDocument;

  @override
  State<_CompactReportRows> createState() => _CompactReportRowsState();
}

class _CompactReportRowsState extends State<_CompactReportRows> {
  static const pageSize = 10;
  int start = 0;

  Widget _field(NativeReportColumn col, Map<String, dynamic> row) {
    final value = plainReportText(row[col.fieldname]);
    final target = _documentType(col, row);
    final number = _numericColumn(col);
    final text = Text(
      value.isEmpty ? '—' : value,
      textAlign: number ? TextAlign.end : TextAlign.start,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
        decoration: target == null ? null : TextDecoration.underline,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              plainReportText(col.label),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: target == null
                ? text
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        alignment: AlignmentDirectional.centerStart,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => widget.onDocument(
                        target,
                        row[col.fieldname].toString(),
                      ),
                      child: text,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final end = math.min(start + pageSize, result.rows.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.rows.length > pageSize)
          Row(
            children: [
              Expanded(
                child: Text('Rows ${start + 1}–$end of ${result.rows.length}'),
              ),
              IconButton(
                tooltip: 'Previous rows',
                icon: const Icon(Icons.chevron_left),
                onPressed: start == 0
                    ? null
                    : () => setState(() => start -= pageSize),
              ),
              IconButton(
                tooltip: 'Next rows',
                icon: const Icon(Icons.chevron_right),
                onPressed: end == result.rows.length
                    ? null
                    : () => setState(() => start += pageSize),
              ),
            ],
          ),
        for (var index = start; index < end; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              border: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final col in result.columns.take(3))
                    _field(col, result.rows[index]),
                  if (result.columns.length > 3)
                    ExpansionTile(
                      key: ValueKey((result, index)),
                      tilePadding: EdgeInsets.zero,
                      title: Text('More fields (${result.columns.length - 3})'),
                      expansionAnimationStyle: workspaceReduceMotion(context)
                          ? AnimationStyle.noAnimation
                          : null,
                      children: [
                        for (final col in result.columns.skip(3))
                          _field(col, result.rows[index]),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
