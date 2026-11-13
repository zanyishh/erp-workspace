import 'ui/access_gate.dart';
import 'knitting_workspace_layout.dart';
import 'mill_overview.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'file_actions.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'knitting_forms.dart';
import 'knitting_models.dart';
import 'knitting_reports.dart';
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';
import 'ui/workspace_art.dart';

part 'knitting_job_workflow.dart';

class KnittingScreen extends StatefulWidget {
  const KnittingScreen({
    super.key,
    required this.api,
    required this.workspace,
    required this.onContextChanged,
    this.onCompany,
    this.onAccount,
    this.onRecords,
    this.onGeneral,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onContextChanged;
  final VoidCallback? onCompany, onAccount, onRecords, onGeneral;
  @override
  State<KnittingScreen> createState() => _KnittingScreenState();
}

class _KnittingScreenState extends State<KnittingScreen> {
  late WorkspaceContext workspace = widget.workspace;
  bool setupDirty = false;
  late Future<KnittingSnapshot> future = widget.api.knittingSnapshot(
    workspace.company!,
  );
  late String page = workspace.destinations.firstOrNull ?? 'Jobs';
  String search = '';
  String? queueFilter;
  Map<String, dynamic>? selected;
  @override
  void didUpdateWidget(covariant KnittingScreen old) {
    super.didUpdateWidget(old);
    workspace = widget.workspace;
    if (old.workspace.company != workspace.company ||
        old.workspace.revision != workspace.revision ||
        old.workspace.accessFingerprint != workspace.accessFingerprint ||
        !workspace.destinations.contains(page)) {
      selected = null;
      page = workspace.destinations.firstOrNull ?? 'Jobs';
      search = '';
      queueFilter = null;
      future = widget.api.knittingSnapshot(
        workspace.company!,
        job: selected?['name'] as String?,
      );
    }
  }

  void refresh() => setState(() {
    future = _reload();
  });
  Future<KnittingSnapshot> _reload() async {
    final fresh = await widget.api.workspaceContext(company: workspace.company);
    if (!mounted) throw const ErpException('Workspace closed.');
    widget.onContextChanged(fresh);
    setState(() {
      workspace = fresh;
      if (!fresh.destinations.contains(page)) {
        selected = null;
        search = '';
        queueFilter = null;
        page = fresh.destinations.firstOrNull ?? 'Jobs';
      }
    });
    if (!fresh.enabled) {
      throw const ErpException(
        'Knitting is not active for this account and company.',
      );
    }
    return widget.api.knittingSnapshot(
      fresh.company!,
      job: selected?['name'] as String?,
    );
  }

  void changedContext(WorkspaceContext fresh) {
    widget.onContextChanged(fresh);
    setState(() {
      workspace = fresh;
      selected = null;
      setupDirty = false;
      queueFilter = null;
      page = fresh.destinations.firstOrNull ?? 'Setup';
      if (fresh.enabled) future = widget.api.knittingSnapshot(fresh.company!);
    });
  }

  Future<void> destination(String value, {String? filter}) async {
    if (!workspace.destinations.contains(value)) return;
    if (page == 'Setup' && setupDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard setup changes?'),
          content: const Text('Your changes have not been applied.'),
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
      if (discard != true || !mounted) return;
    }
    setState(() {
      if (selected != null && (value == 'Overview' || value == 'Jobs')) {
        selected = null;
        future = widget.api.knittingSnapshot(workspace.company!);
      }
      page = value;
      search = '';
      queueFilter = filter;
      setupDirty = false;
    });
  }

  KnitAction? get primary {
    final id = switch (page) {
      'Overview' when workspace.allows('production') => 'produce',
      'Overview' when workspace.allows('quality') => 'quality',
      'Overview' when workspace.allows('planning') => 'plan',
      'Overview' when workspace.allows('billing') => 'invoice',
      'Overview' => 'create_job',
      'Jobs' => 'create_job',
      'Yarn' => 'receive_yarn',
      'Planning' => 'plan',
      'Production' => 'produce',
      'Quality' => 'quality',
      'Delivery' => 'deliver',
      'Billing' => 'invoice',
      'Factory' => 'create_machine',
      _ => null,
    };
    if (selected != null &&
        (page == 'Jobs' || selected?['status'] == 'Completed')) {
      return null;
    }
    return knitActions
        .where(
          (a) =>
              a.id == id &&
              workspace.allows(a.capability) &&
              (id != 'receive_yarn' || a.needsJob == (selected != null)) &&
              (id != 'create_job' || workspace.state == 'Active'),
        )
        .firstOrNull;
  }

  Future<void> action(
    KnitAction spec, {
    Map<String, dynamic> initial = const {},
  }) async {
    final company = workspace.company;
    final access = widget.api.accessRevision;
    final receipt = await Navigator.push(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => KnittingCommandForm(
          api: widget.api,
          workspace: workspace,
          action: spec,
          job: spec.needsJob ? selected : null,
          initial: initial,
        ),
      ),
    );
    if (!mounted) return;
    final job = receipt?['data']?['job'];
    if (const {'create_job', 'job_from_estimate'}.contains(spec.id) &&
        job is String &&
        job.isNotEmpty &&
        workspace.company == company &&
        widget.api.accessReady &&
        access == widget.api.accessRevision &&
        workspace.allows('jobs')) {
      openJob({'name': job});
    } else {
      refresh();
    }
  }

  void openJob(Map<String, dynamic> job) => setState(() {
    selected = job;
    page = 'Jobs';
    search = '';
    queueFilter = null;
    future = widget.api.knittingSnapshot(
      workspace.company!,
      job: job['name'] as String,
    );
  });

  Future<void> printLabel() async {
    try {
      final row = await pickKnitRecord(
        context,
        widget.api,
        workspace.company!,
        'LabelRoll',
        job: selected?['name'] as String?,
      );
      if (row == null) return;
      final r = await widget.api.knittingExport(
        workspace.company!,
        'roll_label',
        {'roll': row['name']},
      );
      if (mounted) {
        await previewFile(
          context,
          r['name'] as String,
          base64Decode(r['content'] as String),
          api: widget.api,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> printDelivery() async {
    try {
      final row = await pickKnitRecord(
        context,
        widget.api,
        workspace.company!,
        'Delivery',
        job: selected?['name'] as String?,
      );
      if (row == null) return;
      final result = await widget.api.knittingExport(
        workspace.company!,
        'delivery_challan',
        {'event': row['name']},
      );
      if (mounted) {
        await previewFile(
          context,
          result['name'] as String,
          base64Decode(result['content'] as String),
          api: widget.api,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> source(String type, String name) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: widget.api,
          doctype: type,
          name: name,
          company: workspace.company,
        ),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      selected = null;
      page = workspace.destinations.firstOrNull ?? 'Jobs';
      queueFilter = null;
      final fresh = _reload();
      setState(() {
        future = fresh;
      });
      await fresh;
    },
    child: KnittingWorkspaceLayout(
      workspace: workspace,
      page: page,
      jobDetail: page == 'Jobs' && selected != null,
      onDestination: destination,
      onCompany: setupDirty ? null : widget.onCompany,
      onAccount: setupDirty ? null : widget.onAccount,
      onRecords: setupDirty ? null : widget.onRecords,
      onGeneral: setupDirty ? null : widget.onGeneral,
      actions: [
        if (page == 'Delivery' && workspace.allows('delivery'))
          OutlinedButton.icon(
            onPressed: printDelivery,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Delivery challan'),
          ),
        if (page == 'Production' || page == 'Quality')
          OutlinedButton.icon(
            onPressed: printLabel,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Roll label'),
          ),
        OutlinedButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
        if (primary != null)
          FilledButton.icon(
            onPressed: () => action(primary!),
            icon: const Icon(Icons.add, size: 18),
            label: Text(primary!.title),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: page == 'Reports'
                ? KnittingReports(
                    api: widget.api,
                    company: workspace.company!,
                    financialRead: workspace.allows('financial_read'),
                    job: selected?['name'] as String?,
                  )
                : page == 'Setup'
                ? _Setup(
                    api: widget.api,
                    workspace: workspace,
                    onSaved: changedContext,
                    onDirty: (value) {
                      if (mounted && value != setupDirty) {
                        setState(() => setupDirty = value);
                      }
                    },
                  )
                : FutureBuilder<KnittingSnapshot>(
                    future: future,
                    builder: (context, state) {
                      if (state.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: "Loading knitting workspace",
                          ),
                        );
                      }
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
                      if (snap.company != workspace.company) {
                        return const SizedBox.shrink();
                      }
                      if (selected != null) {
                        final matches = snap
                            .rows('jobs')
                            .where((j) => j['name'] == selected!['name']);
                        selected = matches.firstOrNull;
                      }
                      if (page == 'Overview') {
                        return MillOverview(
                          api: widget.api,
                          snapshot: snap,
                          workspace: workspace,
                          onDestination: destination,
                          onJob: openJob,
                        );
                      }
                      return KnittingWorkbench(
                        key: ValueKey(page),
                        queueFilter: queueFilter,
                        onFilter: (value) =>
                            setState(() => queueFilter = value),
                        snapshot: snap,
                        page: page,
                        selected: selected,
                        query: search,
                        onQuery: (v) => setState(() => search = v),
                        onJob: openJob,
                        onBack: () => setState(() {
                          selected = null;
                          page = 'Jobs';
                          future = widget.api.knittingSnapshot(
                            workspace.company!,
                          );
                        }),
                        onAction: action,
                        primaryAction: primary,
                        onSource: source,
                        workspace: workspace,
                        onFind: () async {
                          final company = workspace.company!;
                          final access = widget.api.accessRevision;
                          final row = await pickKnitRecord(
                            context,
                            widget.api,
                            company,
                            'Job',
                          );
                          if (row != null &&
                              mounted &&
                              workspace.company == company &&
                              access == widget.api.accessRevision) {
                            openJob(row);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
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
    this.primaryAction,
    this.queueFilter,
    this.onFilter,
  });
  final KnitAction? primaryAction;
  final KnittingSnapshot snapshot;
  final String page, query;
  final String? queueFilter;
  final ValueChanged<String?>? onFilter;
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
                          (a['quantity_kg'] != '0.000' ||
                              (num.tryParse(a['units']?.toString() ?? '0') ??
                                      0) !=
                                  0),
                    )) &&
            (queueFilter == null ||
                (key == 'jobs'
                    ? r['status'] == queueFilter
                    : (key == 'rolls' || key == 'plans') &&
                          r['state'] == queueFilter)) &&
            r.values.join(' ').toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final jobs = rows('jobs');
    final record = selected;
    final balances = record?['balances'] as Map? ?? {};
    final jobPage = page == 'Jobs' && record != null;
    final steps = jobPage
        ? _jobSteps(record, snapshot, workspace)
        : const <_JobStep>[];
    final actions = knitActions.where((a) {
      if (!workspace.allows(a.capability) || a == primaryAction) return false;
      if (a.capability == 'new_job' && workspace.state != 'Active') {
        return false;
      }
      if (record != null && record['status'] == 'Completed') {
        return jobPage && a.id == 'reopen_job';
      }
      if (a.id == 'reopen_job' && record != null) return false;
      if (jobPage) {
        if (!a.needsJob || a.id == steps.first.id || a.id == 'close_job') {
          return false;
        }
        if (const {'deliver', 'invoice', 'quality'}.contains(a.id)) {
          return steps.any((s) => s.id == a.id);
        }
        return true;
      }
      if (page == 'Jobs' && a.id == 'create_job') return false;
      return a.appearsIn(page);
    }).toList();
    bool correction(KnitAction a) => const {
      'revise_job',
      'adjust_yarn',
      'cancel_event',
      'reopen_job',
      'reopen_subcontract',
      'short_close_subcontract',
      'credit_invoice',
      'return_fabric',
      'transfer_fabric',
    }.contains(a.id);
    Widget menuItem(KnitAction a) => MenuItemButton(
      leadingIcon: Icon(_icon(a.group), size: 17),
      onPressed: () => onAction(
        a,
        initial:
            steps.where((s) => s.id == a.id).firstOrNull?.initial ?? const {},
      ),
      child: Text(a.title),
    );
    Widget menu(String label, Iterable<KnitAction> items, IconData icon) {
      return MenuAnchor(
        menuChildren: items.length > 8
            ? [
                for (final group in items.map((a) => a.group).toSet())
                  SubmenuButton(
                    leadingIcon: Icon(_icon(group), size: 17),
                    menuChildren: [
                      for (final a in items.where((a) => a.group == group))
                        menuItem(a),
                    ],
                    child: Text(group),
                  ),
              ]
            : [for (final a in items) menuItem(a)],
        builder: (_, controller, _) => OutlinedButton.icon(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      );
    }

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
          if (jobPage)
            _JobWorkflow(record, steps, workspace, onAction)
          else
            Panel(
              border: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.assignment_outlined, size: 19),
                  Text(
                    record['name'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(record['customer']?.toString() ?? ''),
                  StatusChip(record['status']?.toString() ?? 'Job'),
                ],
              ),
            ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (_, box) {
              final metrics = [
                if (workspace.allows('materials'))
                  ('yarn_kg', 'Yarn in custody', ArtObject.yarn),
                ('fabric_kg', 'Fabric in house', ArtObject.fabric),
                if (workspace.allows('billing'))
                  ('unbilled_kg', 'Awaiting invoice', ArtObject.invoice),
                ('loss_kg', 'Process loss', ArtObject.inspection),
              ];
              final columns = (box.maxWidth / 172).floor().clamp(
                1,
                metrics.length,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (key, label, art) in metrics)
                    SizedBox(
                      width: (box.maxWidth - (columns - 1) * 12) / columns,
                      child: MetricTile(
                        art: WorkspaceArt(art, width: 40, height: 30),
                        label: label,
                        value: '${balances[key] ?? '—'}',
                        footer: 'kg · current job',
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (page == 'Jobs')
            _section(
              'Fabric programme',
              (record['programme'] as List? ?? [])
                  .map(
                    (r) => _row(
                      r['fabric'].toString(),
                      '${r['colour'] ?? 'Natural'} · ${r['dia'] ?? '—'} dia / ${r['gauge'] ?? '—'} G',
                      '${r['target_kg']} kg',
                    ),
                  )
                  .toList(),
              art: ArtObject.fabric,
            ),
        ],
        if (page != 'Jobs' || record == null)
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
        if (record == null && page == 'Jobs' && onFilter != null)
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final status in ['All jobs', 'Running', 'Completed'])
                ChoiceChip(
                  label: Text(status),
                  selected: (queueFilter ?? 'All jobs') == status,
                  onSelected: (_) =>
                      onFilter!(status == 'All jobs' ? null : status),
                ),
            ],
          )
        else if (queueFilter != null && onFilter != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(queueFilter!),
              onDeleted: () => onFilter!(null),
              deleteButtonTooltipMessage: 'Clear queue filter',
            ),
          ),
        if (actions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (actions.any((a) => !correction(a)))
                menu(
                  jobPage
                      ? 'More job entries'
                      : page == 'Jobs'
                      ? 'Job actions'
                      : 'More entries',
                  actions.where((a) => !correction(a)),
                  Icons.add,
                ),
              if (actions.any(correction))
                menu(
                  'Corrections & revisions',
                  actions.where(correction),
                  Icons.history_outlined,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (page != 'Jobs' || record != null) ..._sections(),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: main),
          if (page == 'Jobs' && record == null)
            MillJobRegister(
              sliverWidth: bounds.maxWidth,
              jobs: jobs,
              onJob: onJob,
              showOutput: workspace.allows('production'),
              caption:
                  '${jobs.length} of ${snapshot.rows('jobs').length} recent jobs',
              empty: 'No jobs match this view.',
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
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
  List<Widget> _sections() {
    return [
      if (page == 'Yarn')
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
      if (page == 'Planning')
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
      if (['Production', 'Quality', 'Delivery'].contains(page))
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
      if (page == 'Factory') ...[
        _section(
          'INDUSTRY MASTERS',
          snapshot
              .rows('masters')
              .map(
                (r) => _row(
                  r['title'].toString(),
                  r['category'].toString(),
                  r['enabled'] == 1 ? 'Active' : 'Inactive',
                ),
              )
              .toList(),
        ),
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
      if (queueFilter == null &&
              ['Billing', 'Delivery', 'Production', 'Quality'].contains(page) ||
          page == 'Jobs' && selected != null)
        _section(
          'Posted activity',
          rows('events').map((r) {
            final result = r['result'] as Map? ?? {};
            return _row(
              r['kind'].toString().replaceAll('_', ' '),
              '${r['name']} · ${r['occurred_at']}\n${result['quantity_kg'] != null ? '${result['quantity_kg']} kg' : ''}${r['cancelled'] == 1 ? ' · Cancelled' : ''}',
              result['amount'] != null
                  ? '${workspace.companies.where((c) => c['name'] == workspace.company).firstOrNull?['default_currency'] ?? ''} ${result['amount']}'
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
    if (selected == null) {
      return '${r['general_kg'] ?? '0.000'} kg · ${r['general_units'] ?? '0'} units general';
    }
    final a = (r['allocations'] as List? ?? []).where(
      (a) => a['job'] == selected!['name'],
    );
    return '${a.isEmpty ? '0.000' : a.first['quantity_kg']} kg · ${a.isEmpty ? '0' : a.first['units'] ?? '0'} units allocated';
  }

  Widget _section(String title, List<Widget> children, {ArtObject? art}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Panel(
          border: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (art != null) ...[
                    WorkspaceArt(art, width: 48, height: 36),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Display(title, size: 25)),
                ],
              ),
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

class IndustrySetupScreen extends StatefulWidget {
  const IndustrySetupScreen({
    super.key,
    required this.api,
    required this.workspace,
    required this.onSaved,
    this.onAccount,
    this.onCompany,
  });
  final VoidCallback? onAccount, onCompany;
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onSaved;
  @override
  State<IndustrySetupScreen> createState() => _IndustrySetupScreenState();
}

class _IndustrySetupScreenState extends State<IndustrySetupScreen> {
  bool dirty = false;
  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      await widget.api.industrySettings(widget.workspace.company!);
    },
    child: WorkspacePage(
      title: 'Industry setup',
      subtitle: widget.workspace.company ?? '',
      actions: [
        if (widget.onCompany != null)
          TextButton(
            onPressed: dirty ? null : widget.onCompany,
            child: const Text('Switch company'),
          ),
        if (widget.onAccount != null)
          IconButton(
            onPressed: dirty ? null : widget.onAccount,
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
          ),
      ],
      child: _Setup(
        api: widget.api,
        workspace: widget.workspace,
        onSaved: widget.onSaved,
        onDirty: (value) {
          if (mounted && dirty != value) setState(() => dirty = value);
        },
      ),
    ),
  );
}

class _Setup extends StatefulWidget {
  const _Setup({
    required this.api,
    required this.workspace,
    required this.onSaved,
    this.onDirty,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onSaved;
  final ValueChanged<bool>? onDirty;
  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final key = GlobalKey<FormState>();
  Map<String, dynamic>? values;
  String? error;
  bool saving = false, dirty = false;
  bool? knitting;
  void markDirty() {
    if (!dirty) setState(() => dirty = true);
    widget.onDirty?.call(true);
  }

  Future<void> leaveSetup() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Discard setup changes?"),
        content: const Text("Your changes have not been applied."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Keep editing"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text("Discard changes"),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => dirty = false);
      widget.onDirty?.call(false);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.industrySettings(widget.workspace.company!);
      if (mounted) {
        setState(() {
          knitting =
              widget.workspace.needsIndustrySelection &&
                  widget.workspace.state != 'Setup'
              ? null
              : (r['state'] != 'Inactive' &&
                    widget.workspace.state != 'General ERP');
          values = {
            ...Map<String, dynamic>.from(r['settings'] as Map),
            'state': r['state'],
            'revision': r['revision'],
          };
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> save() async {
    if (knitting == null ||
        (knitting == true && !key.currentState!.validate())) {
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apply industry setup?'),
        content: Text(
          knitting == true
              ? 'Apply the knitting setup to ${widget.workspace.company}? Once active, knitting opens when the team signs in.'
              : 'Use General ERP as the home for ${widget.workspace.company}?',
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
        knitting == true
            ? values!
            : {'state': 'Inactive', 'revision': values!['revision']},
      );
      if (mounted) {
        setState(() {
          values!['revision'] = w.revision;
          dirty = false;
          widget.onDirty?.call(false);
          error = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Industry setup saved.')));
        widget.onSaved(w);
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
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leaveSetup();
      },
      child: ListView(
        children: [
          const Display('Workspace at sign-in', size: 28),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final choice in [false, true])
                ChoiceChip(
                  label: Text(choice ? 'Knitting ERP' : 'General ERP'),
                  avatar: Icon(
                    choice ? Icons.texture : Icons.grid_view,
                    size: 18,
                  ),
                  selected: knitting == choice,
                  onSelected: saving
                      ? null
                      : (_) {
                          markDirty();
                          setState(() {
                            knitting = choice;
                            if (choice &&
                                (values!['state'] == 'Inactive' ||
                                    values!['state'] == 'Setup')) {
                              values!['state'] = 'Active';
                            }
                          });
                        },
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (knitting == false) ...[
            const Text(
              'Open the company dashboard with sales, purchasing, accounts and stock.',
            ),
            const SizedBox(height: 18),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: const Text('Apply general workspace'),
              ),
            ),
          ],
          if (knitting == true)
            Panel(
              border: true,
              child: Form(
                key: key,
                onChanged: markDirty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Display('Knitting setup', size: 30),
                    const SizedBox(height: 12),
                    Text(
                      'Choose the godown and items your mill uses for material receipts and billing.',
                    ),
                    const SizedBox(height: 24),
                    const Display('READINESS', size: 23),
                    const SizedBox(height: 8),
                    for (final (field, label) in [
                      ('warehouse', 'Default godown'),
                      ('service_item', 'Knitting service item'),
                      ('fabric_item', 'Owned fabric item'),
                    ])
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          values![field] != null && values![field] != ''
                              ? Icons.check_circle_outline
                              : Icons.radio_button_unchecked,
                          size: 20,
                        ),
                        title: Text(label),
                      ),
                    const SizedBox(height: 16),
                    for (final (k, label, opts) in [
                      (
                        'state',
                        'Operating status',
                        ['Setup', 'Active', 'Closing'],
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
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
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
                              markDirty();
                              setState(() => values![k] = r['name']);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$label · ${values![k] ?? 'Choose'}',
                                  ),
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
                    const SizedBox(height: 12),
                    const Display('OPERATING SHIFTS', size: 24),
                    const Text(
                      'Machine allocations must fit these hours. A finish earlier than the start runs overnight.',
                    ),
                    const SizedBox(height: 12),
                    for (final shift in values!['shift_windows'] as List? ?? [])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            for (final (field, label) in [
                              ('name', 'Shift'),
                              ('start', 'Start · HH:MM'),
                              ('end', 'Finish · HH:MM'),
                            ]) ...[
                              Expanded(
                                child: TextFormField(
                                  key: ValueKey(
                                    '${identityHashCode(shift)}-$field',
                                  ),
                                  initialValue: shift[field]?.toString(),
                                  decoration: InputDecoration(labelText: label),
                                  onChanged: (v) {
                                    shift[field] = v;
                                    markDirty();
                                  },
                                  validator: (v) => field == 'name'
                                      ? ((v ?? '').trim().isEmpty
                                            ? 'Name the shift'
                                            : null)
                                      : RegExp(
                                          r'^(?:[01]\d|2[0-3]):[0-5]\d$',
                                        ).hasMatch(v ?? '')
                                      ? null
                                      : 'Use HH:MM',
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            IconButton(
                              tooltip: 'Remove shift',
                              onPressed: () {
                                markDirty();
                                setState(
                                  () => (values!['shift_windows'] as List)
                                      .remove(shift),
                                );
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          markDirty();
                          setState(() {
                            (values!['shift_windows'] ??= <dynamic>[]).add(<
                              String,
                              dynamic
                            >{
                              'name':
                                  'Shift ${(values!['shift_windows'] as List).length + 1}',
                              'start': '08:00',
                              'end': '16:00',
                            });
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add shift window'),
                      ),
                    ),
                    const SizedBox(height: 20),
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
      ),
    );
  }
}
