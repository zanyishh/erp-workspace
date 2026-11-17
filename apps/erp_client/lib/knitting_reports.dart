import 'ui/workspace_art.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'file_actions.dart';
import 'knitting_forms.dart';
import 'original_production_report.dart';
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
  String? preset;
  bool get yarnMovement => report == 'yarn_inwards' || report == 'yarn_returns';
  static const presets = <String, (String, String, String)>{
    'roll_status': ('Production Roll Status', 'rolls', ''),
    'roll_time': ('Roll Time Register', 'rolls', ''),
    'shift_stoppage': ('Shiftwise Stoppage', 'stoppage', 'shift'),
    'machine_stoppage': ('Machinewise Stoppage', 'stoppage', 'machine'),
    'hourly_rolls': ('Hourly Roll Register', 'rolls', 'hour'),
    'employee_rolls': (
      'Employee Roll Register',
      'rolls',
      'production_operator',
    ),
    'employee_hourly_rolls': (
      'Employee Hourly Roll Register',
      'rolls',
      'employee_hour',
    ),
    'daily_production': ('Daily Production Report', 'production', 'day'),
    'employee_production': (
      'Employee Production Report',
      'production',
      'production_operator',
    ),
  };
  static const dimensionLabels = {
    'customer': 'Customer / material owner ID',
    'job': 'Order ID',
    'machine': 'Machine ID',
    'operator': 'Operator user ID',
    'production_operator': 'Production operator · original employee',
    'production_machine': 'Original production machine',
    'employee': 'Employee ID',
    'shift': 'Shift',
    'warehouse': 'Godown',
    'source_lot': 'Supplier / customer lot',
    'party_dc_number': 'Party challan number',
    'fabric': 'Fabric',
    'dia': 'Dia',
    'gauge': 'Gauge',
  };
  static const entities = {
    'customer': 'Customer',
    'job': 'Job',
    'machine': 'Machine',
    'operator': 'User',
    'production_operator': 'ProductionOperator',
    'production_machine': 'ProductionMachine',
    'employee': 'Employee',
    'warehouse': 'Warehouse',
  };
  static const dimensions = <String, List<String>>{
    'jobs': ['customer', 'job'],
    'yarn': ['customer', 'job'],
    'yarn_inwards': [
      'customer',
      'job',
      'warehouse',
      'source_lot',
      'party_dc_number',
    ],
    'yarn_returns': ['customer', 'job', 'warehouse', 'source_lot'],
    'fabric': [
      'customer',
      'job',
      'machine',
      'production_machine',
      'operator',
      'production_operator',
      'shift',
      'fabric',
      'dia',
      'gauge',
    ],
    'rolls': [
      'customer',
      'job',
      'machine',
      'production_machine',
      'operator',
      'production_operator',
      'shift',
      'fabric',
      'dia',
      'gauge',
    ],
    'planning': ['customer', 'job', 'machine', 'operator', 'shift'],
    'shortages': ['customer', 'job', 'machine'],
    'changes': ['customer', 'job', 'machine'],
    'unplanned': ['customer', 'job'],
    'production': [
      'customer',
      'job',
      'machine',
      'operator',
      'production_operator',
      'production_machine',
      'shift',
      'fabric',
      'dia',
      'gauge',
    ],
    'quality': ['customer', 'job', 'operator'],
    'subcontract': ['customer', 'job'],
    'components': ['machine'],
    'breakage': [
      'customer',
      'job',
      'machine',
      'operator',
      'employee',
      'fabric',
      'dia',
      'gauge',
    ],
    'stoppage': [
      'customer',
      'job',
      'machine',
      'operator',
      'warehouse',
      'shift',
    ],
    'activity': [
      'customer',
      'job',
      'machine',
      'operator',
      'shift',
      'fabric',
      'dia',
      'gauge',
    ],
    'billing': ['customer', 'job'],
    'margin': ['customer', 'job'],
  };
  final dimensionValues = {
    for (final key in dimensionLabels.keys) key: TextEditingController(),
  };
  final dimensionChoiceLabels = <String, String>{};
  Map<String, String> appliedChoiceLabels = {};
  int start = 0;
  String? error;
  bool exporting = false, showFilters = false;
  late Map<String, dynamic> appliedFilters;
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
    'yarn_inwards': 'Yarn Inward Register',
    'yarn_returns': 'Yarn Return Register',
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
    for (final key in dimensions[report]!)
      if (!(key == 'job' && widget.job != null) &&
          dimensionValues[key]!.text.trim().isNotEmpty)
        key: dimensionValues[key]!.text.trim(),
  };
  String _groupLabel(String key) {
    if (key.isEmpty) return 'Individual records';
    if (key == 'employee_hour') return 'Production employee and hour';
    return const {'production_operator', 'production_machine'}.contains(key)
        ? dimensionLabels[key]!
        : key.replaceAll('_', ' ');
  }

  String _appliedFilterLabel(MapEntry<String, dynamic> entry) {
    final key = entry.key;
    final label = key == 'group_by'
        ? 'Group records'
        : dimensionLabels[key] ?? key.replaceAll('_', ' ');
    final value = key == 'group_by'
        ? _groupLabel(entry.value.toString())
        : const {'production_operator', 'production_machine'}.contains(key)
        ? appliedChoiceLabels[key] ?? 'Selected original reference'
        : entry.value;
    return '$label: $value';
  }

  Future<Map<String, dynamic>> load({bool apply = true}) {
    exporting = false;
    if (apply) appliedChoiceLabels = Map.from(dimensionChoiceLabels);
    appliedFilters = apply ? filters : {...appliedFilters, 'start': start};
    return widget.api.knittingReport(
      widget.company,
      appliedFilters['report'] as String,
      Map.from(appliedFilters),
    );
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    for (final controller in dimensionValues.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KnittingReports old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api ||
        old.company != widget.company ||
        old.job != widget.job ||
        old.financialRead != financialRead) {
      start = 0;
      for (final controller in dimensionValues.values) {
        controller.clear();
      }
      dimensionChoiceLabels.clear();
      if (!financialRead && ['billing', 'margin'].contains(report)) {
        report = 'jobs';
      }
      future = load();
    }
  }

  void refresh({bool apply = true}) => setState(() {
    future = load(apply: apply);
  });
  Future<void> export(String kind) async {
    if (exporting || !widget.api.accessReady) return;
    final api = widget.api;
    final company = widget.company;
    final job = widget.job;
    final access = api.accessRevision;
    final applied = appliedFilters;
    bool current() =>
        mounted &&
        identical(api, widget.api) &&
        company == widget.company &&
        job == widget.job &&
        access == api.accessRevision &&
        api.accessReady &&
        identical(applied, appliedFilters);
    setState(() {
      exporting = true;
      error = null;
    });
    try {
      final f = Map<String, dynamic>.from(applied);
      if (kind == 'roll_label') {
        final row = await pickKnitRecord(
          context,
          api,
          company,
          'LabelRoll',
          job: applied['job'] as String?,
        );
        if (row == null || !current()) return;
        f['roll'] = row['name'];
      }
      final r = await api.knittingExport(company, kind, f);
      if (!mounted || !current()) return;
      final bytes = base64Decode(r['content'] as String);
      if (r['mime'] == 'application/pdf') {
        await previewFile(context, r['name'] as String, bytes, api: api);
      } else {
        await saveOrShareFile(
          context,
          r['name'] as String,
          bytes,
          mime: r['mime'] as String,
          canContinue: current,
        );
      }
    } catch (e) {
      if (current()) setState(() => error = e.toString());
    } finally {
      if (current()) setState(() => exporting = false);
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
    key: ValueKey((widget.api, widget.company, widget.job)),
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
      for (final controller in dimensionValues.values) {
        controller.clear();
      }
      dimensionChoiceLabels.clear();
      final fresh = load();
      setState(() {
        future = fresh;
      });
      await fresh;
    },
    child: LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxWidth < 650 || bounds.maxHeight < 750;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.job == null &&
                widget.api.contextFor(widget.company)?.canReadImportedHistory ==
                    true)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OriginalProductionReport(
                        api: widget.api,
                        company: widget.company,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Original production reports'),
                ),
              ),
            if (compact)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => showFilters = !showFilters),
                  icon: Icon(
                    showFilters ? Icons.arrow_back : Icons.tune,
                    size: 18,
                  ),
                  label: Text(
                    showFilters ? 'Back to results' : 'Report options',
                  ),
                ),
              ),
            if (compact && showFilters)
              Expanded(
                child: ListView(
                  children: [_controls(), const Divider(), _providers()],
                ),
              )
            else ...[
              if (!compact)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: bounds.maxHeight * .48,
                  ),
                  child: SingleChildScrollView(child: _controls()),
                ),
              if (compact)
                Text(
                  presets[preset]?.$1 ?? labels[report]!,
                  style: displayStyle(22),
                ),
              const SizedBox(height: 12),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(child: _results(phone: bounds.maxWidth < 650)),
              if (!compact) ...[const Divider(), _providers()],
            ],
          ],
        );
      },
    ),
  );

  Widget _controls() => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<String>(
          key: ValueKey(('report', financialRead, preset)),
          isExpanded: true,
          initialValue: preset ?? report,
          decoration: const InputDecoration(labelText: 'Report'),
          items: [
            for (final e in labels.entries)
              if (financialRead || !['billing', 'margin'].contains(e.key))
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            for (final option in presets.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value.$1)),
          ],
          onChanged: (v) {
            setState(() {
              final option = presets[v];
              preset = option == null ? null : v;
              report = option?.$2 ?? v!;
              start = 0;
              group = option?.$3 ?? '';
              if (option != null || yarnMovement) {
                showFilters = false;
                if (mode != 'period') {
                  mode = 'period';
                  if (option != null) from.text = to.text;
                }
              }
              kind = '';
              for (final key in dimensionValues.keys) {
                if (!dimensions[report]!.contains(key)) {
                  dimensionValues[key]!.clear();
                  dimensionChoiceLabels.remove(key);
                }
              }
              future = load();
            });
          },
        ),
      ),
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(('time-basis', preset)),
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Time basis'),
          items: const [
            DropdownMenuItem(value: 'as_of', child: Text('As of end date')),
            DropdownMenuItem(value: 'period', child: Text('Period movement')),
          ],
          onChanged: (v) {
            setState(() {
              mode = v!;
              if (mode != 'period') preset = null;
            });
          },
        ),
      ),
      if (mode == 'period')
        SizedBox(
          width: 180,
          child: TextField(
            controller: from,
            decoration: const InputDecoration(labelText: 'From · YYYY-MM-DD'),
          ),
        ),
      SizedBox(
        width: 180,
        child: TextField(
          controller: to,
          decoration: const InputDecoration(labelText: 'Through · YYYY-MM-DD'),
        ),
      ),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String>(
          key: ValueKey('group-${preset ?? report}'),
          isExpanded: true,
          initialValue: group,
          decoration: const InputDecoration(labelText: 'Group records'),
          items: [
            for (final key in [
              '',
              'customer',
              if (yarnMovement) ...[
                'day',
                'hour',
                'warehouse',
                'source_lot',
              ] else ...[
                'machine',
                'operator',
                if (dimensions[report]!.contains('production_operator')) ...[
                  'production_operator',
                  'production_machine',
                ],
                'employee',
                'gauge',
                'shift',
                'day',
                'hour',
                if (report == 'rolls') 'employee_hour',
                'fabric',
                'dia',
                'programme_line',
                'kind',
              ],
            ])
              DropdownMenuItem(value: key, child: Text(_groupLabel(key))),
          ],
          onChanged: (v) {
            setState(() {
              group = v!;
              if (group != presets[preset]?.$3) preset = null;
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
              const DropdownMenuItem(value: '', child: Text('All actions')),
              for (final action in {
                for (final a in knitActions) a.id: a,
              }.values)
                DropdownMenuItem(
                  value: action.id,
                  child: Text(action.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              kind = v!;
            }),
          ),
        ),
      for (final key in dimensions[report]!)
        if (!(key == 'job' && widget.job != null))
          SizedBox(
            width: 240,
            child:
                const {
                  'production_operator',
                  'production_machine',
                }.contains(key)
                ? _originalProductionFilter(key)
                : TextField(
                    key: ValueKey('report-filter-$key'),
                    controller: dimensionValues[key],
                    onChanged: key == 'machine'
                        ? (value) {
                            if (value.trim().isNotEmpty) {
                              setState(() {
                                dimensionValues['production_machine']!.clear();
                                dimensionChoiceLabels.remove(
                                  'production_machine',
                                );
                              });
                            }
                          }
                        : null,
                    decoration: InputDecoration(
                      labelText: dimensionLabels[key],
                      hintText: 'All · or exact historical value',
                      suffixIcon: entities.containsKey(key)
                          ? IconButton(
                              tooltip: 'Choose ${entities[key]}',
                              icon: const Icon(Icons.search),
                              onPressed: () => _pickDimension(key),
                            )
                          : null,
                    ),
                  ),
          ),
      if (widget.job != null) Text('Order fixed: ${widget.job}'),
      const SizedBox(
        width: 300,
        child: Text(
          'Type an exact saved value for historical or inactive records. Choices show active records. Customer means material owner.',
          style: TextStyle(fontSize: 11),
        ),
      ),
      FilledButton.icon(
        onPressed: () {
          start = 0;
          showFilters = false;
          refresh();
        },
        icon: const Icon(Icons.play_arrow_outlined, size: 18),
        label: const Text('Run report'),
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
            PopupMenuItem(value: 'gst_review', child: Text('GST review JSON')),
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
  );

  Future<void> _pickDimension(String key) async {
    final api = widget.api;
    final sourceJob = widget.job;
    final company = widget.company, kind = report, access = api.accessRevision;
    final row = await pickKnitRecord(
      context,
      api,
      company,
      entities[key]!,
      job: sourceJob,
    );
    if (!mounted ||
        row == null ||
        !identical(api, widget.api) ||
        sourceJob != widget.job ||
        company != widget.company ||
        kind != report ||
        access != widget.api.accessRevision ||
        !widget.api.accessReady) {
      return;
    }
    setState(() {
      dimensionValues[key]!.text = row['name']?.toString() ?? '';
      if (const {'machine', 'production_machine'}.contains(key)) {
        final other = key == 'machine' ? 'production_machine' : 'machine';
        dimensionValues[other]!.clear();
        dimensionChoiceLabels.remove(other);
      }
      if (key == 'production_operator') {
        dimensionChoiceLabels[key] = knittingProductionOperatorTitle(row);
      } else if (key == 'production_machine') {
        dimensionChoiceLabels[key] = knittingProductionMachineTitle(row);
      }
    });
  }

  Widget _originalProductionFilter(String key) => InkWell(
    key: ValueKey('report-filter-$key'),
    onTap: () => _pickDimension(key),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: dimensionLabels[key],
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dimensionValues[key]!.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear ${key.replaceAll('_', ' ')}',
                onPressed: () => setState(() {
                  dimensionValues[key]!.clear();
                  dimensionChoiceLabels.remove(key);
                }),
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: key == 'production_machine'
                  ? 'Choose original machine'
                  : 'Choose original employee',
              onPressed: () => _pickDimension(key),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
      child: Text(
        dimensionChoiceLabels[key] ??
            (key == 'production_machine'
                ? 'All original machines'
                : 'All original employees'),
      ),
    ),
  );

  Widget _providers() => Wrap(
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
  );
  Widget _results({required bool phone}) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, state) {
      if (state.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.hasError) {
        return MessagePanel(
          title: 'REPORT COULD NOT LOAD',
          message: state.error.toString(),
          action: () => refresh(apply: false),
        );
      }
      if (!state.hasData) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading report'),
        );
      }
      final r = state.data!,
          cols = List<Map<String, dynamic>>.from(
            (r['columns'] as List)
                .map((c) => Map<String, dynamic>.from(c))
                .where(
                  (c) => !const {
                    'production_operator_record',
                    'production_operator',
                    'production_machine_record',
                    'production_machine',
                  }.contains(c['key']),
                ),
          ),
          rows = List<Map<String, dynamic>>.from(
            (r['rows'] as List).map((c) => Map<String, dynamic>.from(c)),
          );
      final summary = <Widget>[
        Text(
          'Applied: ${appliedFilters.entries.where((e) => !['start', 'report', 'mode'].contains(e.key)).map(_appliedFilterLabel).join(' · ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${r['row_count']} records · ${r['mode']} · Through ${r['to_date']}\n${r['basis']}',
            style: const TextStyle(fontSize: 11, color: WorkspaceTheme.muted),
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
                    '${e.key.toString().replaceAll('_', ' ')}: ${e.value ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
      ];
      final pager = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: start > 0
                ? () {
                    start -= 100;
                    refresh(apply: false);
                  }
                : null,
            child: const Text('Previous'),
          ),
          Text(
            rows.isEmpty
                ? '0 of ${r['row_count']}'
                : '${(r['start'] as int) + 1}–${(r['start'] as int) + rows.length} of ${r['row_count']}',
          ),
          TextButton(
            onPressed: r['has_more'] == true
                ? () {
                    start += 100;
                    refresh(apply: false);
                  }
                : null,
            child: const Text('Next'),
          ),
        ],
      );
      if (phone) {
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: ValueKey(future),
                slivers: [
                  SliverList.list(children: summary),
                  if (rows.isEmpty)
                    const SliverToBoxAdapter(
                      child: MessagePanel(
                        title: 'NO MATCHING RECORDS',
                        message: 'Change the dates, job or report to see matching activity.',
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) =>
                          _phoneRecord(cols, rows[index], index),
                    ),
                ],
              ),
            ),
            pager,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...summary,
          Expanded(
            child: rows.isEmpty
                ? const MessagePanel(
                    title: 'NO MATCHING RECORDS',
                    message: 'Change the dates, job or report to see matching activity.',
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: cols.length * 165.0,
                      child: Column(
                        children: [
                          Container(
                            color: const Color(0xFFE5E5E1),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                for (final c in cols)
                                  SizedBox(
                                    width: 165,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final c in cols)
                                      SizedBox(
                                        width: 165,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
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
          pager,
        ],
      );
    },
  );

  Widget _phoneRecord(
    List<Map<String, dynamic>> columns,
    Map<String, dynamic> row,
    int index,
  ) {
    Widget field(Map<String, dynamic> column) {
      final key = column['key'] as String;
      final numeric =
          key.endsWith('_kg') ||
          const {
            'minutes',
            'units',
            'records',
            'roll_count',
            'net_amount',
            'tax_amount',
            'grand_total',
            'outstanding',
            'quantity',
          }.contains(key);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                column['label'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: _cell(key, row[key], numeric: numeric)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        border: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final column in columns.take(3)) field(column),
            if (columns.length > 3)
              ExpansionTile(
                key: ValueKey((future, index)),
                title: Text('More fields (${columns.length - 3})'),
                tilePadding: EdgeInsets.zero,
                expansionAnimationStyle: workspaceReduceMotion(context)
                    ? AnimationStyle.noAnimation
                    : null,
                children: [for (final column in columns.skip(3)) field(column)],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String key, dynamic value, {bool numeric = false}) {
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
            textAlign: numeric ? TextAlign.end : TextAlign.start,
            style: TextStyle(
              fontSize: 12,
              fontFeatures: numeric
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          );
  }
}
