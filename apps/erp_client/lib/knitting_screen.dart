import 'package:flutter/material.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'knitting_forms.dart';
import 'knitting_models.dart';
import 'knitting_reports.dart';
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';

class KnittingScreen extends StatefulWidget {
  const KnittingScreen({
    super.key,
    required this.api,
    required this.workspace,
    required this.onContextChanged,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onContextChanged;
  @override
  State<KnittingScreen> createState() => _KnittingScreenState();
}

class _KnittingScreenState extends State<KnittingScreen> {
  late Future<KnittingSnapshot> future = widget.api.knittingSnapshot(
    widget.workspace.company!,
  );
  String page = 'Jobs', search = '';
  Map<String, dynamic>? selected;
  @override
  void didUpdateWidget(covariant KnittingScreen old) {
    super.didUpdateWidget(old);
    if (old.workspace.company != widget.workspace.company ||
        old.workspace.revision != widget.workspace.revision) {
      selected = null;
      page = 'Jobs';
      search = '';
      future = widget.api.knittingSnapshot(
        widget.workspace.company!,
        job: selected?['name'] as String?,
      );
    }
  }

  void refresh() => setState(
    () => future = widget.api.knittingSnapshot(
      widget.workspace.company!,
      job: selected?['name'] as String?,
    ),
  );
  Future<void> action(
    KnitAction spec, {
    Map<String, dynamic> initial = const {},
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => KnittingCommandForm(
          api: widget.api,
          workspace: widget.workspace,
          action: spec,
          job: spec.needsJob ? selected : null,
          initial: initial,
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> source(String type, String name) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: widget.api,
          doctype: type,
          name: name,
          company: widget.workspace.company,
        ),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
    title: 'Knitting',
    subtitle: '${widget.workspace.company} · ${widget.workspace.state}',
    actions: [
      OutlinedButton.icon(
        onPressed: refresh,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
      ),
      if (widget.workspace.allows('new_job') &&
          widget.workspace.state == 'Active')
        FilledButton.icon(
          onPressed: () => action(knitActions.first),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New job'),
        ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceSelection(
          labels: widget.workspace.destinations,
          selected: page,
          onSelected: (v) => setState(() {
            page = v;
            search = '';
          }),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: page == 'Reports'
              ? KnittingReports(
                  api: widget.api,
                  company: widget.workspace.company!,
                  financialRead: widget.workspace.allows('financial_read'),
                  job: selected?['name'] as String?,
                )
              : page == 'Setup'
              ? _Setup(
                  api: widget.api,
                  workspace: widget.workspace,
                  onSaved: widget.onContextChanged,
                )
              : FutureBuilder<KnittingSnapshot>(
                  future: future,
                  builder: (context, state) {
                    if (state.hasError) {
                      return MessagePanel(
                        title: 'COULD NOT LOAD KNITTING',
                        message: state.error.toString(),
                        action: refresh,
                      );
                    }
                    if (!state.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Loading knitting records',
                        ),
                      );
                    }
                    final snap = state.data!;
                    if (snap.company != widget.workspace.company) {
                      return const SizedBox.shrink();
                    }
                    if (selected != null) {
                      final matches = snap
                          .rows('jobs')
                          .where((j) => j['name'] == selected!['name']);
                      if (matches.isNotEmpty) selected = matches.first;
                    }
                    return KnittingWorkbench(
                      snapshot: snap,
                      page: page,
                      selected: selected,
                      query: search,
                      onQuery: (v) => setState(() => search = v),
                      onJob: (j) => setState(() {
                        selected = j;
                        future = widget.api.knittingSnapshot(
                          widget.workspace.company!,
                          job: j['name'] as String,
                        );
                      }),
                      onBack: () => setState(() {
                        selected = null;
                        future = widget.api.knittingSnapshot(
                          widget.workspace.company!,
                        );
                      }),
                      onAction: action,
                      onSource: source,
                      workspace: widget.workspace,
                      onFind: () async {
                        final row = await pickKnitRecord(
                          context,
                          widget.api,
                          widget.workspace.company!,
                          'Job',
                        );
                        if (row != null) {
                          final fresh = await widget.api.knittingLookup(
                            widget.workspace.company!,
                            'Job',
                            row['name'] as String,
                          );
                          if (mounted) {
                            final rows = fresh['rows'] as List;
                            setState(() {
                              selected = Map<String, dynamic>.from(
                                rows.firstWhere((r) => r['name'] == row['name'])
                                    as Map,
                              );
                              future = widget.api.knittingSnapshot(
                                widget.workspace.company!,
                                job: row['name'] as String,
                              );
                            });
                          }
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class KnittingWorkbench extends StatelessWidget {
  const KnittingWorkbench({
    super.key,
    required this.snapshot,
    required this.page,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onJob,
    required this.onBack,
    required this.onAction,
    required this.onSource,
    required this.workspace,
    required this.onFind,
  });
  final KnittingSnapshot snapshot;
  final String page, query;
  final Map<String, dynamic>? selected;
  final ValueChanged<String> onQuery;
  final ValueChanged<Map<String, dynamic>> onJob;
  final VoidCallback onBack, onFind;
  final Future<void> Function(KnitAction, {Map<String, dynamic> initial})
  onAction;
  final Future<void> Function(String, String) onSource;
  final WorkspaceContext workspace;
  List<Map<String, dynamic>> rows(String key) => snapshot
      .rows(key)
      .where(
        (r) =>
            (selected == null ||
                r['job'] == selected!['name'] ||
                key == 'lots' &&
                    (r['allocations'] as List? ?? []).any(
                      (a) =>
                          a['job'] == selected!['name'] &&
                          a['quantity_kg'] != '0.000',
                    )) &&
            r.values.join(' ').toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final jobs = rows('jobs');
    final record = selected;
    final balances = record?['balances'] as Map? ?? {};
    final actions = knitActions
        .where(
          (a) =>
              workspace.allows(a.capability) &&
              a.group == page &&
              (record == null ||
                  record['status'] == 'Running' ||
                  a.id == 'reopen_job'),
        )
        .toList();
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (record != null) ...[
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('All jobs'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
          Panel(
            dark: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Display(record['name'].toString(), size: 32, light: true),
                    StatusChip(
                      record['status']?.toString() ?? 'Job',
                      dark: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${record['customer']} · ${record['material_mode']} material · Due ${record['due_date'] ?? 'not set'}',
                  style: const TextStyle(color: WorkspaceTheme.light),
                ),
                const SizedBox(height: 18),
                Text(
                  'TARGET  ${record['target_kg']} kg',
                  style: const TextStyle(
                    color: WorkspaceTheme.palePeach,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WorkspaceSteps(current: _stage(balances)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (key, label) in [
                ('yarn_kg', 'Yarn in custody'),
                ('fabric_kg', 'Fabric in house'),
                ('unbilled_kg', 'Awaiting invoice'),
                ('loss_kg', 'Process loss'),
              ])
                SizedBox(
                  width: 170,
                  child: MetricTile(
                    label: label,
                    value: '${balances[key] ?? '—'}',
                    footer: 'kg · current job',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (page == 'Jobs')
            _section(
              'FABRIC PROGRAMME',
              (record['programme'] as List? ?? [])
                  .map(
                    (r) => _row(
                      r['id'].toString(),
                      '${r['fabric']} · ${r['colour'] ?? 'Natural'} · ${r['dia'] ?? '—'} dia / ${r['gauge'] ?? '—'} G',
                      '${r['target_kg']} kg',
                    ),
                  )
                  .toList(),
            ),
        ] else if (page == 'Jobs') ...[
          _jobSummary(snapshot),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('$page-${record?['name']}'),
                decoration: InputDecoration(
                  labelText: page == 'Jobs'
                      ? 'Filter loaded jobs'
                      : 'Filter loaded records',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: onQuery,
              ),
            ),
            if (page == 'Jobs') ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onFind,
                child: const Text('Find any job'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (page == 'Jobs' && record == null) ...[
          Text(
            '${jobs.length} recent jobs · Search all records with Find any job',
            style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          for (final job in jobs) _jobCard(job),
          if (jobs.isEmpty)
            _empty('No jobs match this view. Create a job to begin.'),
        ] else
          ..._sections(),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Display('AVAILABLE ACTIONS', size: 25),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in actions)
                OutlinedButton.icon(
                  onPressed: () => onAction(a, initial: const {}),
                  icon: Icon(_icon(a.group), size: 16),
                  label: Text(a.title),
                ),
            ],
          ),
        ],
      ],
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [main],
    );
  }

  IconData _icon(String group) => switch (group) {
    'Yarn' => Icons.inventory_2_outlined,
    'Production' => Icons.precision_manufacturing_outlined,
    'Quality' => Icons.verified_outlined,
    'Billing' => Icons.receipt_long_outlined,
    'Planning' => Icons.calendar_month_outlined,
    _ => Icons.arrow_forward,
  };
  int _stage(Map b) {
    for (final (key, i) in [
      ('billed_kg', 5),
      ('delivered_kg', 4),
      ('produced_kg', 3),
      ('received_kg', 2),
    ]) {
      if (b[key] != null && Kg.parse(b[key].toString()).milli > BigInt.zero) {
        return i;
      }
    }
    return 0;
  }

  Widget _jobSummary(KnittingSnapshot s) => LayoutBuilder(
    builder: (context, c) => Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: c.maxWidth > 750 ? c.maxWidth * .44 : c.maxWidth,
          child: Panel(
            dark: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FACTORY WORKSPACE',
                  style: TextStyle(
                    color: WorkspaceTheme.palePeach,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                const Display('EVERY ROLL.\nCONNECTED.', size: 42, light: true),
                const SizedBox(height: 16),
                Text(
                  '${s.rows('jobs').where((j) => j['status'] == 'Running').length} active jobs in the recent view',
                  style: const TextStyle(color: WorkspaceTheme.light),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Programme → yarn → roll → invoice',
                  style: TextStyle(
                    color: WorkspaceTheme.palePeach,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final (label, count, foot) in [
          (
            'Awaiting QC',
            s.rows('rolls').where((r) => r['state'] == 'Awaiting QC').length,
            'rolls to inspect',
          ),
          (
            'On hold',
            s.rows('rolls').where((r) => r['state'] == 'On Hold').length,
            'rolls blocked',
          ),
          (
            'Ready to send',
            s.rows('rolls').where((r) => r['state'] == 'Released').length,
            'released rolls',
          ),
        ])
          SizedBox(
            width: c.maxWidth > 1000
                ? (c.maxWidth * .56 - 64) / 3
                : c.maxWidth > 600
                ? (c.maxWidth - 32) / 3
                : c.maxWidth,
            child: MetricTile(
              label: label,
              value: '$count',
              footer: '$foot · recent view',
            ),
          ),
      ],
    ),
  );
  Widget _jobCard(Map<String, dynamic> job) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Panel(
      border: true,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 12,
        ),
        title: Text(
          job['name'].toString(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${job['customer']}\n${job['target_kg']} kg · ${job['material_mode']} · ${job['due_date'] ?? 'No due date'}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusChip(job['status'].toString()),
            const Icon(Icons.arrow_forward, size: 16),
          ],
        ),
        onTap: () => onJob(job),
      ),
    ),
  );
  List<Widget> _sections() {
    const all = false;
    return [
      if (all || page == 'Yarn')
        _section(
          'YARN LOTS',
          rows('lots')
              .map(
                (r) => _row(
                  r['name'].toString(),
                  '${r['item']} · ${r['material_owner']} · ${r['party'] ?? workspace.company}',
                  _allocation(r),
                ),
              )
              .toList(),
        ),
      if (all || page == 'Planning')
        _section(
          'MACHINE QUEUE',
          rows('plans')
              .map(
                (r) => _row(
                  r['machine'].toString(),
                  '${r['job']}\n${r['starts_at']} → ${r['ends_at']}',
                  '${r['quantity_kg']} kg',
                ),
              )
              .toList(),
        ),
      if (all || ['Production', 'Quality', 'Delivery'].contains(page))
        _section(
          'ROLLS & QUALITY',
          rows('rolls')
              .map(
                (r) => _row(
                  r['name'].toString(),
                  '${r['job']} · ${r['machine'] ?? 'Manual'} · ${r['state']}',
                  '${r['weight_kg']} kg',
                ),
              )
              .toList(),
        ),
      if (all || page == 'Factory') ...[
        _section(
          'MACHINES',
          snapshot
              .rows('machines')
              .map(
                (r) => _row(
                  r['title'].toString(),
                  '${r['dia']} dia · ${r['gauge']} gauge · ${r['knit_type']}',
                  '${r['capacity_kg']} kg / 8h',
                ),
              )
              .toList(),
        ),
        _section(
          'COMPONENT LIFE',
          snapshot
              .rows('components')
              .map(
                (r) => _row(
                  '${r['component_type']} · ${r['machine']}',
                  'Run ${r['run_kg']} / ${r['boundary_kg']} kg',
                  '${r['remaining_kg']} kg left',
                ),
              )
              .toList(),
        ),
        _section(
          'SUBCONTRACTS',
          rows('subcontracts')
              .map(
                (r) => _row(
                  r['name'].toString(),
                  '${r['supplier']} · ${r['status']}',
                  '${r['target_kg']} kg',
                  onTap: r['purchase_order'] != null
                      ? () => onSource(
                          'Purchase Order',
                          r['purchase_order'].toString(),
                        )
                      : null,
                ),
              )
              .toList(),
        ),
        _section(
          'FACTORY CALENDAR',
          snapshot
              .rows('holidays')
              .map(
                (r) => _row(
                  r['date'].toString(),
                  r['description']?.toString() ?? 'Holiday',
                  r['machine']?.toString() ?? 'Whole factory',
                ),
              )
              .toList(),
        ),
      ],
      if (all ||
          ['Billing', 'Delivery', 'Production', 'Quality'].contains(page) ||
          page == 'Jobs' && selected != null)
        _section(
          'POSTED ACTIVITY',
          rows('events').map((r) {
            final result = r['result'] as Map? ?? {};
            return _row(
              r['kind'].toString().replaceAll('_', ' '),
              '${r['name']} · ${r['occurred_at']}\n${result['quantity_kg'] != null ? '${result['quantity_kg']} kg' : ''}${r['cancelled'] == 1 ? ' · Cancelled' : ''}',
              result['amount'] != null
                  ? '₹${result['amount']}'
                  : result['decision']?.toString() ?? '',
              onTap: result['voucher'] != null
                  ? () => onSource(
                      result['voucher_type'].toString(),
                      result['voucher'].toString(),
                    )
                  : null,
            );
          }).toList(),
        ),
      if (page == 'Billing')
        _section(
          'AGREED RATES',
          snapshot
              .rows('rates')
              .map(
                (r) => _row(
                  '${r['customer']} · ${r['fabric']}',
                  '${r['yarn_count'] ?? ''} / ${r['gauge'] ?? ''} · ${r['effective_from']}',
                  '${r['rate']} / kg',
                ),
              )
              .toList(),
        ),
    ];
  }

  String _allocation(Map r) {
    if (selected == null) return '${r['general_kg'] ?? '0.000'} kg general';
    final a = (r['allocations'] as List? ?? []).where(
      (a) => a['job'] == selected!['name'],
    );
    return '${a.isEmpty ? '0.000' : a.first['quantity_kg']} kg allocated';
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Display(title, size: 25),
          const SizedBox(height: 14),
          if (children.isEmpty)
            _empty('Nothing recorded here yet.')
          else
            ...children,
        ],
      ),
    ),
  );
  Widget _row(
    String title,
    String detail,
    String amount, {
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 480
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: WorkspaceTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(amount),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          detail,
                          style: const TextStyle(
                            color: WorkspaceTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(amount),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(Icons.open_in_new, size: 16),
                    ),
                ],
              ),
      ),
    ),
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(text, style: const TextStyle(color: WorkspaceTheme.muted)),
  );
}

class IndustrySetupScreen extends StatelessWidget {
  const IndustrySetupScreen({
    super.key,
    required this.api,
    required this.workspace,
    required this.onSaved,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onSaved;
  @override
  Widget build(BuildContext context) => WorkspacePage(
    title: 'Industry setup',
    subtitle: workspace.company ?? '',
    child: _Setup(api: api, workspace: workspace, onSaved: onSaved),
  );
}

class _Setup extends StatefulWidget {
  const _Setup({
    required this.api,
    required this.workspace,
    required this.onSaved,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onSaved;
  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final key = GlobalKey<FormState>();
  Map<String, dynamic>? values;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.industrySettings(widget.workspace.company!);
      if (mounted) {
        setState(
          () => values = {
            ...Map<String, dynamic>.from(r['settings'] as Map),
            'state': r['state'],
            'revision': r['revision'],
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apply industry setup?'),
        content: Text(
          'Save ${values!['state']} for ${widget.workspace.company}. Permissions still control each user’s access. Existing jobs and accounting records remain linked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Apply setup'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => saving = true);
    try {
      final w = await widget.api.configureIndustry(
        widget.workspace.company!,
        values!,
      );
      if (mounted) {
        widget.onSaved(w);
        setState(() {
          values!['revision'] = w.revision;
          error = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Industry setup saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (values == null) {
      return error != null
          ? MessagePanel(
              title: 'SETUP UNAVAILABLE',
              message: error!,
              action: load,
            )
          : const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        Panel(
          border: true,
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Display('KNITTING INDUSTRY PACK', size: 30),
                const SizedBox(height: 12),
                Text(
                  'Policy revision ${values!['revision']} · General ERP stays available.\nConfigure shared items and accounts in General ERP, then select them here.',
                ),
                const SizedBox(height: 24),
                for (final (k, label, opts) in [
                  (
                    'state',
                    'Pack state',
                    ['Setup', 'Active', 'Closing', 'Inactive'],
                  ),
                  (
                    'lycra_charge',
                    'Owned auxiliary material charge',
                    ['Included', 'Separate'],
                  ),
                  (
                    'rate_lookup',
                    'Party rate matching',
                    ['Fabric', 'FabricCountGauge'],
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: values![k]?.toString() ?? opts.first,
                      decoration: InputDecoration(labelText: label),
                      items: opts
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => values![k] = v,
                    ),
                  ),
                for (final (k, label, entity) in [
                  ('warehouse', 'Default godown', 'Warehouse'),
                  ('service_item', 'Non-stock service item', 'Item'),
                  ('fabric_item', 'Owned fabric stock item', 'Item'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton(
                      onPressed: () async {
                        final r = await pickKnitRecord(
                          context,
                          widget.api,
                          widget.workspace.company!,
                          entity,
                        );
                        if (r != null && mounted) {
                          setState(() => values![k] = r['name']);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('$label · ${values![k] ?? 'Choose'}'),
                            ),
                            const Icon(Icons.search, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final (k, label, defaultValue) in [
                  ('number_prefix', 'Document prefix', 'KN'),
                  (
                    'allow_production_excess_pct',
                    'Permitted excess production · %',
                    '0',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      initialValue: values![k]?.toString() ?? defaultValue,
                      decoration: InputDecoration(labelText: label),
                      onChanged: (v) => values![k] = v,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter a value.' : null,
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFA23F38)),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving…' : 'Review & apply setup'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
