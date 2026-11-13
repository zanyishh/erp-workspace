import 'ui/workspace_art.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'file_actions.dart';
import 'knitting_forms.dart';
import 'widgets.dart';
import 'ui/access_gate.dart';

class KnittingReports extends StatefulWidget {
  const KnittingReports({
    super.key,
    required this.api,
    required this.company,
    required this.financialRead,
    this.job,
  });
  final ErpApi api;
  final String company;
  final bool financialRead;
  final String? job;
  @override
  State<KnittingReports> createState() => _KnittingReportsState();
}

class _KnittingReportsState extends State<KnittingReports> {
  bool get financialRead =>
      widget.api.contextFor(widget.company)?.allows('financial_read') ??
      widget.financialRead;
  String report = 'jobs', mode = 'as_of', group = '';
  String kind = '';
  int start = 0;
  String? error;
  bool exporting = false;
  final from = TextEditingController(
    text:
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-01',
  );
  final to = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  late Future<Map<String, dynamic>> future = load();
  final labels = {
    'jobs': 'Job reconciliation',
    'yarn': 'Yarn custody',
    'fabric': 'Fabric in house',
    'rolls': 'Roll traceability',
    'planning': 'Machine allocations',
    'shortages': '72-hour yarn coverage',
    'changes': '24-hour job changes',
    'unplanned': 'Planning status',
    'production': 'Production & loss',
    'quality': 'Quality history',
    'subcontract': 'Subcontract reconciliation',
    'components': 'Component life',
    'breakage': 'Component breakage',
    'stoppage': 'Machine stoppage',
    'activity': 'Transaction register',
    'billing': 'Source billing',
    'margin': 'Margin before overhead',
  };
  Map<String, dynamic> get filters => {
    'mode': mode,
    if (mode == 'period') 'from_date': from.text,
    'to_date': to.text,
    'start': start,
    if (widget.job != null) 'job': widget.job,
    'report': report,
    if (group.isNotEmpty) 'group_by': group,
    if (report == 'activity' && kind.isNotEmpty) 'kind': kind,
  };
  Future<Map<String, dynamic>> load() =>
      widget.api.knittingReport(widget.company, report, filters);
  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KnittingReports old) {
    super.didUpdateWidget(old);
    if (old.company != widget.company ||
        old.job != widget.job ||
        old.financialRead != financialRead) {
      start = 0;
      if (!financialRead && ['billing', 'margin'].contains(report)) {
        report = 'jobs';
      }
      future = load();
    }
  }

  void refresh() => setState(() {
    future = load();
  });
  Future<void> export(String kind) async {
    if (exporting) return;
    setState(() {
      exporting = true;
      error = null;
    });
    try {
      final f = Map<String, dynamic>.from(filters);
      if (kind == 'roll_label') {
        final row = await pickKnitRecord(
          context,
          widget.api,
          widget.company,
          'LabelRoll',
        );
        if (row == null) return;
        f['roll'] = row['name'];
      }
      final r = await widget.api.knittingExport(widget.company, kind, f);
      if (!mounted) return;
      final bytes = base64Decode(r['content'] as String);
      if (r['mime'] == 'application/pdf') {
        await previewFile(context, r['name'] as String, bytes, api: widget.api);
      } else {
        await saveOrShareFile(
          context,
          r['name'] as String,
          bytes,
          mime: r['mime'] as String,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> open(String type, String name) => Navigator.push(
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
    fullPage: false,
    revalidate: () async {
      final access = widget.api.contextFor(widget.company);
      if (access == null || !access.allows('reports')) {
        throw const ErpException('Your access to these reports changed.');
      }
      if (!financialRead && ['billing', 'margin'].contains(report)) {
        report = 'jobs';
      }
      error = null;
      start = 0;
      final fresh = load();
      setState(() {
        future = fresh;
      });
      await fresh;
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey('report-$financialRead'),
                isExpanded: true,
                initialValue: report,
                decoration: const InputDecoration(labelText: 'Report'),
                items: [
                  for (final e in labels.entries)
                    if (financialRead || !['billing', 'margin'].contains(e.key))
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  setState(() {
                    report = v!;
                    start = 0;
                    future = load();
                  });
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Time basis'),
                items: const [
                  DropdownMenuItem(
                    value: 'as_of',
                    child: Text('As of end date'),
                  ),
                  DropdownMenuItem(
                    value: 'period',
                    child: Text('Period movement'),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    mode = v!;
                    start = 0;
                    future = load();
                  });
                },
              ),
            ),
            if (mode == 'period')
              SizedBox(
                width: 180,
                child: TextField(
                  controller: from,
                  decoration: const InputDecoration(
                    labelText: 'From · YYYY-MM-DD',
                  ),
                ),
              ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: to,
                decoration: const InputDecoration(
                  labelText: 'Through · YYYY-MM-DD',
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Group records'),
                items: [
                  for (final key in [
                    '',
                    'customer',
                    'machine',
                    'operator',
                    'employee',
                    'gauge',
                    'shift',
                    'day',
                    'hour',
                    'fabric',
                    'dia',
                    'programme_line',
                    'kind',
                  ])
                    DropdownMenuItem(
                      value: key,
                      child: Text(
                        key.isEmpty
                            ? 'Individual records'
                            : key.replaceAll('_', ' '),
                      ),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    group = v!;
                    start = 0;
                    future = load();
                  });
                },
              ),
            ),
            if (report == 'activity')
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All actions'),
                    ),
                    for (final action in {
                      for (final a in knitActions) a.id: a,
                    }.values)
                      DropdownMenuItem(
                        value: action.id,
                        child: Text(
                          action.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    kind = v!;
                    start = 0;
                    future = load();
                  }),
                ),
              ),
            FilledButton(
              onPressed: () {
                start = 0;
                refresh();
              },
              child: const Text('Run report'),
            ),
            PopupMenuButton<String>(
              enabled: !exporting,
              onSelected: export,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'csv', child: Text('Save CSV')),
                const PopupMenuItem(value: 'pdf', child: Text('Preview PDF')),
                const PopupMenuItem(
                  value: 'roll_label',
                  child: Text('Print roll label'),
                ),
                if (financialRead) ...const [
                  PopupMenuItem(
                    value: 'gst_review',
                    child: Text('GST review JSON'),
                  ),
                  PopupMenuItem(
                    value: 'tally_review',
                    child: Text('Tally review XML'),
                  ),
                ],
              ],
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(exporting ? 'Preparing file…' : 'Export / print ▾'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFA23F38)),
            ),
          ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.hasError) {
                return MessagePanel(
                  title: 'REPORT COULD NOT LOAD',
                  message: state.error.toString(),
                  action: refresh,
                );
              }
              if (!state.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading report',
                  ),
                );
              }
              final r = state.data!,
                  cols = List<Map<String, dynamic>>.from(
                    (r['columns'] as List).map(
                      (c) => Map<String, dynamic>.from(c),
                    ),
                  ),
                  rows = List<Map<String, dynamic>>.from(
                    (r['rows'] as List).map(
                      (c) => Map<String, dynamic>.from(c),
                    ),
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${r['row_count']} records · ${r['mode']} · Through ${r['to_date']}\n${r['basis']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: WorkspaceTheme.muted,
                      ),
                    ),
                  ),
                  if ((r['summary'] as Map).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 10,
                        children: [
                          for (final e in (r['summary'] as Map).entries)
                            Text(
                              '${e.key.toString().replaceAll('_', ' ')}: ${e.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: rows.isEmpty
                        ? const MessagePanel(
                            title: 'NO MATCHING RECORDS',
                            message:
                                'Change the dates, job or report to see matching activity.',
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: cols.length * 165.0,
                              child: Column(
                                children: [
                                  Container(
                                    color: const Color(0xFFE5E5E1),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        for (final c in cols)
                                          SizedBox(
                                            width: 165,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                              child: ColumnCaption(
                                                c['label'] as String,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: rows.length,
                                      itemBuilder: (_, i) => Container(
                                        decoration: BoxDecoration(
                                          color: i.isEven
                                              ? WorkspaceTheme.surface
                                              : null,
                                          border: const Border(
                                            bottom: BorderSide(
                                              color: WorkspaceTheme.border,
                                              width: .5,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final c in cols)
                                              SizedBox(
                                                width: 165,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 16,
                                                      ),
                                                  child: _cell(
                                                    c['key'] as String,
                                                    rows[i][c['key']],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: start > 0
                            ? () {
                                start -= 100;
                                refresh();
                              }
                            : null,
                        child: const Text('Previous'),
                      ),
                      Text(
                        '${r['start']}–${(r['start'] as int) + rows.length} of ${r['row_count']}',
                      ),
                      TextButton(
                        onPressed: r['has_more'] == true
                            ? () {
                                start += 100;
                                refresh();
                              }
                            : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const Divider(),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final name in ['E-Invoice', 'E-Way Bill', 'Payment gateway'])
              ActionChip(
                label: Text('$name · Not configured'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('$name is not configured'),
                    content: const Text(
                      'Choose a provider and test credentials in a separate setup step. This version has no connected submission or payment provider. Review exports can be saved locally.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
  Widget _cell(String key, dynamic value) {
    final type = switch (key) {
      'job' => 'Knitting Job',
      'invoice' => 'Sales Invoice',
      'lot' => 'Knitting Material Lot',
      'plan' => 'Knitting Plan',
      'subcontract' => 'Knitting Subcontract',
      _ => null,
    };
    return type != null && value != null
        ? InkWell(
            onTap: () => open(type, value.toString()),
            child: Text(
              value.toString(),
              style: const TextStyle(
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          )
        : SelectableText(
            value?.toString() ?? '—',
            style: const TextStyle(fontSize: 12),
          );
  }
}
