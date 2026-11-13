import 'ui/access_gate.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'document_editor.dart';
import 'file_actions.dart';
import 'document_fields.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'native_reports.dart';
import 'widgets.dart';

class NativeReportScreen extends StatefulWidget {
  const NativeReportScreen({
    super.key,
    required this.api,
    required this.name,
    this.company,
  });
  final ErpApi api;
  final String name;
  final String? company;
  @override
  State<NativeReportScreen> createState() => _NativeReportScreenState();
}

class _NativeReportScreenState extends State<NativeReportScreen> {
  late Future<Map<String, dynamic>> _definition = widget.api.reportDefinition(
    widget.name,
    company: widget.company,
  );
  Map<String, dynamic>? _values;
  Map<String, String> _errors = {};
  Future<NativeReportResult>? _result;
  bool _busy = false, _queued = false;
  String? _error;
  String _filterKey = '';

  Map<String, dynamic> _filters(NativeSchema schema) => {
    for (final f in schema.fields.where((f) => !f.layout && !f.hidden))
      if (_values![f.name] != null && _values![f.name] != '')
        f.name: f.parse(_values![f.name]),
  };
  void _run(NativeSchema schema) {
    final invalid = schema.validate(_values!);
    if (invalid.isNotEmpty) {
      setState(() => _errors = invalid);
      return;
    }
    final filters = _filters(schema);
    final key = jsonEncode(filters);
    if (key != _filterKey) _queued = false;
    _filterKey = key;
    setState(() {
      _errors = {};
      _error = null;
      _result = widget.api.runReport(widget.name, filters);
    });
  }

  Future<void> _queue(NativeSchema schema) async {
    if (_busy || _queued) return;
    setState(() => _busy = true);
    try {
      final pending = _result;
      await widget.api.queueReport(widget.name, _filters(schema));
      if (mounted && identical(_result, pending)) {
        _queued = true;
        _run(schema);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(String type, String name) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DocumentEditor(
        api: widget.api,
        doctype: type,
        name: name,
        company: widget.company,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      _result = null;
      final fresh = widget.api.reportDefinition(
        widget.name,
        company: widget.company,
      );
      setState(() {
        _definition = fresh;
      });
      await fresh;
    },
    child: Scaffold(
      appBar: AppBar(title: Display(widget.name.toUpperCase(), size: 27)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _definition,
        builder: (context, state) {
          if (state.hasError) {
            return MessagePanel(
              title: 'COULD NOT OPEN REPORT',
              message: state.error.toString(),
              action: () => setState(() {
                _definition = widget.api.reportDefinition(
                  widget.name,
                  company: widget.company,
                );
              }),
            );
          }
          if (!state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final definition = state.data!;
          final schema = NativeSchema.fromJson(definition);
          _values ??= objectMap(
            jsonDecode(jsonEncode(definition['defaults'] ?? {})),
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  border: true,
                  frosted: true,
                  child: ExpansionTile(
                    expansionAnimationStyle:
                        MediaQuery.disableAnimationsOf(context)
                        ? AnimationStyle.noAnimation
                        : const AnimationStyle(
                            duration: Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                          ),
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: const Display('REPORT FILTERS', size: 25),
                    children: [
                      DocumentFields(
                        schema: schema,
                        data: _values!,
                        errors: _errors,
                        onChanged: () => setState(() {
                          _result = null;
                          _queued = false;
                          _errors = {};
                          _error = null;
                        }),
                        onLink: (type, query, field) => widget.api.searchLinks(
                          type,
                          query,
                          parent: definition['reference'] as String,
                          field: field.name,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _run(schema),
                          icon: const Icon(Icons.play_arrow_outlined),
                          label: const Text('Run report'),
                        ),
                      ),
                    ],
                  ),
                ),
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
                  FutureBuilder<NativeReportResult>(
                    future: _result,
                    builder: (context, result) {
                      if (result.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(36),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (result.hasError) {
                        return MessagePanel(
                          title: 'REPORT COULD NOT RUN',
                          message: result.error.toString(),
                          action: () => _run(schema),
                        );
                      }
                      final report = result.data!;
                      if (report.pending) {
                        return MessagePanel(
                          title: _queued
                              ? 'REPORT IS BEING PREPARED'
                              : 'PREPARED REPORT',
                          message: _queued
                              ? 'Your report is running in the background. Refresh to check its results.'
                              : 'Generate this report in the background, then refresh to view the results.',
                          label: _queued
                              ? 'Refresh results'
                              : 'Generate report',
                          action: _busy
                              ? null
                              : _queued
                              ? () => _run(schema)
                              : () => _queue(schema),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children: [
                              Display('${report.rows.length} ROWS', size: 25),
                              if (enabled(definition['can_export']))
                                TextButton.icon(
                                  onPressed: report.rows.isEmpty
                                      ? null
                                      : () async {
                                          try {
                                            await saveOrShareFile(
                                              context,
                                              '${widget.name}.csv',
                                              Uint8List.fromList(
                                                utf8.encode(report.csv()),
                                              ),
                                              mime: 'text/csv',
                                            );
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(e.toString()),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.save_alt, size: 18),
                                  label: const Text('Export CSV'),
                                ),
                              if (enabled(definition['can_export']))
                                TextButton.icon(
                                  onPressed: report.rows.isEmpty
                                      ? null
                                      : () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: report.csv()),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'CSV copied for your spreadsheet.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copy CSV'),
                                ),
                            ],
                          ),
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
                                      footer:
                                          item['currency']?.toString() ?? '',
                                    ),
                                  ),
                              ],
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
                              : NativeReportTable(
                                  result: report,
                                  onDocument: _open,
                                ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
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
  Widget build(BuildContext context) => SingleChildScrollView(
    child: PaginatedDataTable(
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
              child: Text(
                plainReportText(col.label),
                maxLines: 2,
                textAlign: _numericColumn(col)
                    ? TextAlign.right
                    : TextAlign.left,
              ),
            ),
          ),
      ],
      source: _ReportRows(result, onDocument),
    ),
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
    final type = col.type == 'Dynamic Link'
        ? row[col.options]?.toString()
        : col.type == 'Link'
        ? col.options
        : null;
    final linked =
        type != null &&
        type.isNotEmpty &&
        value is String &&
        value.isNotEmpty &&
        !value.startsWith('<');
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
            decoration: linked ? TextDecoration.underline : null,
          ),
        ),
      ),
      onTap: linked ? () => onDocument(type, value) : null,
    );
  }
}
