import 'ui/access_gate.dart';
import 'knitting_workspace_layout.dart';
import 'mill_overview.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'file_actions.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'erp_models.dart';
import 'knitting_forms.dart';
import 'knitting_models.dart';
import 'knitting_register.dart';
import 'native_models.dart';
import 'knitting_reports.dart';
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';
import 'ui/workspace_art.dart';

part 'knitting_job_workflow.dart';
part 'knitting_workflow_views.dart';

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
    this.onInvoices,
    this.invoiceWorkspace,
    this.onInvoicePreview,
    this.onHistory,
    this.onBusinessModule,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onContextChanged;
  final VoidCallback? onCompany, onAccount, onRecords, onGeneral, onInvoices;
  final Future<void> Function(String company, String name)? onInvoicePreview;
  final Widget Function(
    Widget jobBilling,
    Future<void> Function()? billFromDelivery,
    VoidCallback refreshBilling,
  )?
  invoiceWorkspace;
  final ValueChanged<ErpModule>? onBusinessModule;
  final ValueChanged<String>? onHistory;
  @override
  State<KnittingScreen> createState() => _KnittingScreenState();
}

typedef _MillLocation = ({
  String page,
  String? job,
  String query,
  String? filter,
  String? estimateFromDate,
  String? estimateToDate,
  Map<String, dynamic>? jobCustomer,
  String? jobFromDate,
  String? jobToDate,
  String? masterCategory,
  Map<String, int> starts,
});

class _KnittingScreenState extends State<KnittingScreen> {
  final _history = <_MillLocation>[];
  final _searchField = TextEditingController();
  final _workflowScope = ValueNotifier(0);
  bool _drawerOpen = false;
  Rect? _jobOrigin;
  Map<String, int> pageStarts = {};
  _MillLocation get _location => (
    page: page,
    job: selected?['name'] as String?,
    query: search,
    filter: queueFilter,
    estimateFromDate: estimateFromDate,
    estimateToDate: estimateToDate,
    jobCustomer: jobCustomer == null ? null : Map.unmodifiable(jobCustomer!),
    jobFromDate: jobFromDate,
    jobToDate: jobToDate,
    masterCategory: masterCategory,
    starts: Map.unmodifiable(pageStarts),
  );

  void _remember() {
    // A drawer destination is a peer. Back on repeated visits should never loop
    // through an unbounded list of identical workspaces.
    final current = _location;
    _history.removeWhere(
      (row) => row.page == current.page && row.job == current.job,
    );
    _history.add(current);
  }

  void _resetNavigation() {
    _jobOrigin = null;
    _history.clear();
    _searchField.clear();
    search = '';
    queueFilter = null;
    estimateFromDate = null;
    estimateToDate = null;
    jobCustomer = null;
    jobFromDate = null;
    jobToDate = null;
    masterCategory = null;
    pageStarts = {};
  }

  @override
  void dispose() {
    _searchField.dispose();
    _workflowScope.dispose();
    super.dispose();
  }

  late WorkspaceContext workspace = widget.workspace;
  bool setupDirty = false;
  late Future<KnittingSnapshot> future = widget.api.knittingSnapshot(
    workspace.company!,
  );
  late String page = workspace.destinations.firstOrNull ?? 'Jobs';
  String search = '';
  String? queueFilter, estimateFromDate, estimateToDate, jobFromDate, jobToDate;
  Map<String, dynamic>? jobCustomer;
  String? masterCategory;
  Map<String, dynamic>? selected;
  @override
  void didUpdateWidget(covariant KnittingScreen old) {
    super.didUpdateWidget(old);
    workspace = widget.workspace;
    if (!identical(old.api, widget.api) ||
        old.workspace.company != workspace.company ||
        old.workspace.revision != workspace.revision ||
        old.workspace.accessFingerprint != workspace.accessFingerprint ||
        !workspace.destinations.contains(page)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _workflowScope.value++;
      });
      selected = null;
      page = workspace.destinations.firstOrNull ?? 'Jobs';
      _resetNavigation();
      setupDirty = false;
      future = widget.api.knittingSnapshot(
        workspace.company!,
        job: selected?['name'] as String?,
      );
    }
  }

  void refresh() => setState(() {
    _jobOrigin = null;
    pageStarts = {};
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
        _resetNavigation();
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
      _resetNavigation();
      page = fresh.destinations.firstOrNull ?? 'Setup';
      if (fresh.enabled) future = widget.api.knittingSnapshot(fresh.company!);
    });
  }

  Future<bool> _canLeave() async {
    if (page != 'Setup' || !setupDirty) return true;
    return await _confirmDiscardSetup(context) && mounted;
  }

  Future<void> _back() async {
    if (!await _canLeave() || !mounted || _history.isEmpty) return;
    setState(() {
      _jobOrigin = null;
      final previous = _history.removeLast();
      if (previous.job != selected?['name']) {
        selected = previous.job == null ? null : {'name': previous.job};
        future = widget.api.knittingSnapshot(
          workspace.company!,
          job: previous.job,
        );
      }
      page = previous.page;
      search = previous.query;
      _searchField.text = search;
      queueFilter = previous.filter;
      estimateFromDate = previous.estimateFromDate;
      estimateToDate = previous.estimateToDate;
      jobCustomer = previous.jobCustomer;
      jobFromDate = previous.jobFromDate;
      jobToDate = previous.jobToDate;
      masterCategory = previous.masterCategory;
      pageStarts = Map.of(previous.starts);
      setupDirty = false;
    });
  }

  Future<void> destination(String value, {String? filter}) async {
    if (!workspace.destinations.contains(value)) return;
    final showRegister = const {
      'Overview',
      'Jobs',
      'Estimation',
      'Billing',
    }.contains(value);
    if (page == value &&
        _location.filter == filter &&
        (!showRegister || selected == null)) {
      return;
    }
    if (!await _canLeave() || !mounted) return;
    setState(() {
      _jobOrigin = null;
      if (page != value || (showRegister && selected != null)) _remember();
      if (selected != null && showRegister) {
        selected = null;
        future = widget.api.knittingSnapshot(workspace.company!);
      }
      page = value;
      search = '';
      _searchField.clear();
      queueFilter = filter;
      estimateFromDate = null;
      estimateToDate = null;
      jobCustomer = null;
      jobFromDate = null;
      jobToDate = null;
      masterCategory = null;
      pageStarts = {};
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
      'Estimation' => 'create_estimate',
      'Subcontracting' => 'create_subcontract',
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
              a.availableIn(workspace) &&
              (id != 'receive_yarn' || a.needsJob == (selected != null)) &&
              (id != 'create_job' || workspace.state == 'Active'),
        )
        .firstOrNull;
  }

  Future<void> action(
    KnitAction spec, {
    Map<String, dynamic> initial = const {},
    Map<String, dynamic>? sourceJob,
    Map<String, Map<String, dynamic>> initialReferences = const {},
  }) async {
    final company = workspace.company;
    final origin = workspace;
    final source = sourceJob ?? selected;
    final access = widget.api.accessRevision;
    final receipt = await Navigator.push(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => KnittingCommandForm(
          api: widget.api,
          workspace: origin,
          action: spec,
          job: spec.needsJob ? source : null,
          initial: initial,
          initialReferences: initialReferences,
          onInvoicePreview: widget.onInvoicePreview == null || company == null
              ? null
              : (name) => widget.onInvoicePreview!(company, name),
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

  Future<void> openRoll(KnitAction spec, Map<String, dynamic> roll) async {
    final company = workspace.company!;
    final access = widget.api.accessRevision;
    final jobName = roll['job'] as String;
    final route = ModalRoute.of(context);
    final originalPage = page;
    try {
      final results = await Future.wait<Object>([
        widget.api.knittingSnapshot(company, job: jobName),
        widget.api.knittingRoll(company, jobName, roll['name'] as String),
      ]);
      final source = results[0] as KnittingSnapshot;
      final current = results[1] as Map<String, dynamic>;
      if (!mounted ||
          workspace.company != company ||
          page != originalPage ||
          route?.isCurrent == false ||
          widget.api.accessRevision != access ||
          !widget.api.accessReady) {
        return;
      }
      final job = source
          .rows('jobs')
          .where((j) => j['name'] == jobName)
          .firstOrNull;
      if (job == null || job['status'] != 'Running') {
        throw const ErpException(
          'This job is no longer available for new entries. Refresh the queue.',
        );
      }
      if (current['name'] != roll['name'] ||
          current['job'] != jobName ||
          current['company'] != company ||
          current['state'] != roll['state']) {
        throw const ErpException(
          'The roll changed after this queue loaded. Refresh the queue to see its current state.',
        );
      }
      await action(
        spec,
        sourceJob: job,
        initial: spec.id == 'deliver'
            ? {
                'rolls': [roll['name']],
              }
            : {'roll': roll['name']},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void openJob(Map<String, dynamic> job, {Rect? origin}) => setState(() {
    _remember();
    _searchField.clear();
    selected = job;
    _jobOrigin = origin;
    page = 'Jobs';
    search = '';
    queueFilter = null;
    pageStarts = {};
    future = widget.api.knittingSnapshot(
      workspace.company!,
      job: job['name'] as String,
    );
  });

  Future<void> _printRecord(String entity, String format, String field) async {
    final api = widget.api;
    final company = workspace.company!;
    final job = selected?['name'] as String?;
    final revision = api.accessRevision;
    final fingerprint = workspace.accessFingerprint;
    final originPage = page;
    bool current() =>
        mounted &&
        identical(api, widget.api) &&
        api.accessReady &&
        api.accessRevision == revision &&
        workspace.company == company &&
        workspace.accessFingerprint == fingerprint &&
        page == originPage &&
        selected?['name'] == job;

    try {
      final row = await pickKnitRecord(context, api, company, entity, job: job);
      if (row == null || !current()) return;
      final file = await api.knittingExport(company, format, {
        field: row['name'],
      });
      if (!mounted || !current()) return;
      await previewFile(
        context,
        file['name'] as String,
        base64Decode(file['content'] as String),
        api: api,
      );
    } catch (e) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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

  (String, String) get _originalRecords => switch (page) {
    'Production' || 'Quality' => ('Original production', 'production'),
    'Delivery' => ('Original deliveries', 'delivery'),
    'Yarn' => ('Original yarn receipts', 'yarn_receipt'),
    'Billing' => ('Original invoices', 'invoice'),
    'Factory' => ('Original masters', 'master'),
    _ => ('Original orders', 'job'),
  };

  bool get _billingIntegrated =>
      widget.invoiceWorkspace != null &&
      workspace.destinations.contains('Billing');
  bool get _invoiceWorkspaceOpen => _billingIntegrated && page == 'Billing';

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      selected = null;
      _resetNavigation();
      setupDirty = false;
      page = workspace.destinations.firstOrNull ?? 'Jobs';
      final fresh = _reload();
      setState(() {
        future = fresh;
      });
      await fresh;
    },
    child: PopScope(
      canPop: _history.isEmpty || _drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_drawerOpen && _history.isNotEmpty) _back();
      },
      child: KnittingWorkspaceLayout(
        onDrawerChanged: (open) => setState(() => _drawerOpen = open),
        onBack: _history.isEmpty ? null : _back,
        backLabel: _history.isEmpty
            ? null
            : (_history.last.page == 'Jobs' && _history.last.job != null
                  ? 'Back to job details'
                  : 'Back to ${_history.last.page.toLowerCase()}'),
        workspace: workspace,
        page: page,
        jobDetail: page == 'Jobs' && selected != null,
        onDestination: destination,
        onCompany: setupDirty ? null : widget.onCompany,
        onAccount: setupDirty ? null : widget.onAccount,
        onRecords: setupDirty ? null : widget.onRecords,
        onInvoices: setupDirty || _billingIntegrated ? null : widget.onInvoices,
        onHistory: setupDirty || widget.onHistory == null
            ? null
            : () => widget.onHistory!('job'),
        onGeneral: setupDirty ? null : widget.onGeneral,
        onBusinessModule: setupDirty ? null : widget.onBusinessModule,
        actions: [
          if (!_invoiceWorkspaceOpen &&
              page == 'Billing' &&
              widget.onInvoices != null)
            OutlinedButton.icon(
              onPressed: widget.onInvoices,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Invoice register'),
            ),
          if (!_invoiceWorkspaceOpen && widget.onHistory != null && !setupDirty)
            OutlinedButton.icon(
              onPressed: () => widget.onHistory!(_originalRecords.$2),
              icon: const Icon(Icons.history_outlined, size: 18),
              label: Text(_originalRecords.$1),
            ),
          if (page == 'Delivery' && workspace.allows('delivery'))
            OutlinedButton.icon(
              onPressed: () =>
                  _printRecord('Delivery', 'delivery_challan', 'event'),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Delivery challan'),
            ),
          if (page == 'Production' || page == 'Quality')
            OutlinedButton.icon(
              onPressed: () => _printRecord('LabelRoll', 'roll_label', 'roll'),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Roll label'),
            ),
          if (!_invoiceWorkspaceOpen && page != 'Reports' && page != 'Setup')
            IconButton.outlined(
              tooltip: 'Refresh knitting records',
              onPressed: refresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          if (!_invoiceWorkspaceOpen && primary != null)
            FilledButton.icon(
              onPressed: () => action(primary!),
              icon: Icon(primary!.icon, size: 18),
              label: Text(primary!.title),
            ),
        ],
        child: _invoiceWorkspaceOpen
            ? widget.invoiceWorkspace!(
                _workbench(),
                primary == null ? null : _billFromDelivery,
                refresh,
              )
            : _workbench(),
      ),
    ),
  );
  Future<void> _billFromDelivery() async {
    final bill = primary;
    if (_invoiceWorkspaceOpen && bill != null && widget.api.accessReady) {
      await action(bill);
    }
  }

  Widget _workbench() => page == 'Reports'
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
          parentHandlesBack: _history.isNotEmpty,
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
                onJobFromRow: openJob,
                onOriginalProduction: widget.onHistory == null
                    ? null
                    : () => widget.onHistory!('production'),
              );
            }
            if (page == 'Estimation') {
              return _EstimateRegister(
                api: widget.api,
                snapshot: snap,
                workspace: workspace,
                query: search,
                searchField: _searchField,
                onQuery: (value) => setState(() {
                  search = value;
                  pageStarts = {};
                }),
                start: pageStarts['estimates'] ?? 0,
                onPage: (value) =>
                    setState(() => pageStarts = {'estimates': value}),
                fromDate: estimateFromDate,
                toDate: estimateToDate,
                onDates: (from, to) => setState(() {
                  estimateFromDate = from;
                  estimateToDate = to;
                  pageStarts = {};
                }),
                onOpen: _openEstimate,
              );
            }
            return KnittingWorkbench(
              key: ValueKey(page),
              masterCategory: masterCategory,
              onMasterCategory: (value) => setState(() {
                masterCategory = value;
                pageStarts = {...pageStarts, 'masters': 0};
              }),
              onMaster: _openMaster,
              jobCustomer: jobCustomer,
              jobFromDate: jobFromDate,
              jobToDate: jobToDate,
              onJobFilters: (customer, from, to) => setState(() {
                jobCustomer = customer == null ? null : Map.from(customer);
                jobFromDate = from;
                jobToDate = to;
                pageStarts = {};
              }),
              queueFilter: queueFilter,
              onFilter: (value) => setState(() {
                queueFilter = value;
                pageStarts = {};
              }),
              api: widget.api,
              pageStarts: pageStarts,
              onPage: (key, start) => setState(() {
                pageStarts = {...pageStarts, key: start};
              }),
              snapshot: snap,
              page: page,
              selected: selected,
              query: search,
              searchField: _searchField,
              onQuery: (v) => setState(() {
                search = v;
                pageStarts = {};
              }),
              onJob: openJob,
              onJobFromRow: openJob,
              jobOrigin: _jobOrigin,
              onAction: action,
              onRoll: openRoll,
              primaryAction: primary,
              onSource: source,
              onSubcontract: _openSubcontract,
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
    required this.onAction,
    required this.onSource,
    required this.workspace,
    required this.onFind,
    this.searchField,
    this.primaryAction,
    this.queueFilter,
    this.onFilter,
    this.onRoll,
    this.api,
    this.pageStarts = const {},
    this.onPage,
    this.onSubcontract,
    this.jobCustomer,
    this.jobFromDate,
    this.jobToDate,
    this.onJobFilters,
    this.masterCategory,
    this.onMasterCategory,
    this.onMaster,
    this.onJobFromRow,
    this.jobOrigin,
  });
  final String? masterCategory;
  final ValueChanged<String?>? onMasterCategory;
  final ValueChanged<Map<String, dynamic>>? onMaster;
  final Map<String, dynamic>? jobCustomer;
  final String? jobFromDate, jobToDate;
  final void Function(Map<String, dynamic>?, String?, String?)? onJobFilters;
  final ValueChanged<Map<String, dynamic>>? onSubcontract;
  final ErpApi? api;
  final Map<String, int> pageStarts;
  final void Function(String, int)? onPage;
  final KnitAction? primaryAction;
  final KnittingSnapshot snapshot;
  final String page, query;
  final String? queueFilter;
  final ValueChanged<String?>? onFilter;
  final Future<void> Function(KnitAction, Map<String, dynamic>)? onRoll;
  final Map<String, dynamic>? selected;
  final ValueChanged<String> onQuery;
  final ValueChanged<Map<String, dynamic>> onJob;
  final MillJobRowAction? onJobFromRow;
  final Rect? jobOrigin;
  final VoidCallback onFind;
  final TextEditingController? searchField;
  final Future<void> Function(KnitAction, {Map<String, dynamic> initial})
  onAction;
  final Future<void> Function(String, String) onSource;
  final WorkspaceContext workspace;
  List<Map<String, dynamic>> rows(String key) => snapshot
      .rows(key)
      .where(
        (r) =>
            (page != 'Billing' ||
                key != 'events' ||
                const {
                  'invoice',
                  'credit_invoice',
                  'bill_yarn',
                  'subcontract_bill',
                  'migration_delivery_reference',
                  'migration_billing_initialization',
                }.contains(r['kind'])) &&
            (selected == null ||
                const {
                  'masters',
                  'machines',
                  'components',
                  'holidays',
                  'rates',
                }.contains(key) ||
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
            r.values
                .join(' ')
                .toLowerCase()
                .contains(query.trim().toLowerCase()),
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
    final originalProgramme = record != null && _hasOriginalProgramme(record);
    final actions = knitActions.where((a) {
      if (const {'accept_estimate', 'job_from_estimate'}.contains(a.id)) {
        return false;
      }
      if (originalProgramme && a.id == 'revise_job') return false;
      if (!a.availableIn(workspace) || a == primaryAction) return false;
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
      if (page == 'Subcontracting') return _subcontractActions.contains(a.id);
      return a.appearsIn(page);
    }).toList();
    bool correction(KnitAction a) => const {
      'revise_job',
      'revise_rate',
      'adjust_yarn',
      'cancel_event',
      'reopen_job',
      'reopen_subcontract',
      'short_close_subcontract',
      'credit_invoice',
      'return_fabric',
      'transfer_fabric',
    }.contains(a.id);
    final visibleActions = actions
        .where(
          (a) =>
              (!jobPage || a.id == 'revise_rate') &&
              _visibleWorkflowActions.contains(a.id),
        )
        .toList();
    final remainingActions = actions
        .where((a) => !visibleActions.contains(a))
        .toList();
    Widget menuItem(KnitAction a) => MenuItemButton(
      leadingIcon: Icon(a.icon, size: 17),
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
          if (jobPage)
            _JobCardExpansion(
              key: ValueKey(record['name']),
              origin: jobOrigin,
              child: _JobWorkflow(record, steps, workspace, onAction),
            )
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
                    knittingJobTitle(record),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (knittingJobTitle(record) != record['name'])
                    Text(record['name'].toString()),
                  Text(knittingCustomerTitle(record, fallback: '')),
                  if (record['job_date'] != null)
                    Text('Order date ${record['job_date']}'),
                  StatusChip(record['status']?.toString() ?? 'Job'),
                ],
              ),
            ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (_, box) {
              final metrics = [
                if (workspace.allows('materials'))
                  ('yarn_kg', 'Yarn in custody', Icons.all_inbox_outlined),
                ('fabric_kg', 'Fabric in house', Icons.layers_outlined),
                if (workspace.allows('billing'))
                  (
                    'unbilled_kg',
                    'Awaiting invoice',
                    Icons.receipt_long_outlined,
                  ),
                ('loss_kg', 'Process loss', Icons.scale_outlined),
              ];
              final columns = (box.maxWidth / 172).floor().clamp(
                1,
                metrics.length,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (key, label, icon) in metrics)
                    SizedBox(
                      width: (box.maxWidth - (columns - 1) * 12) / columns,
                      child: MetricTile(
                        icon: icon,
                        accented: false,
                        label: label,
                        value: '${balances[key] ?? '—'}',
                        footer: record['reconciliation_available'] == false
                            ? 'Balance unavailable'
                            : key == 'loss_kg' &&
                                  balances['captured_produced_kg'] != null
                            ? 'kg · since stock capture'
                            : 'kg · current job',
                      ),
                    ),
                ],
              );
            },
          ),
          if (balances['captured_produced_kg'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Production includes ${balances['captured_produced_kg']} kg recorded before stock capture. Original dated transactions remain in Imported history.',
                style: const TextStyle(color: WorkspaceTheme.muted),
              ),
            ),
          if (balances['captured_delivered_kg'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Original delivery totals include ${balances['captured_delivered_kg']} kg delivered and ${balances['captured_billed_kg']} kg already billed. New invoices apply only to the remaining delivery quantities.',
                style: const TextStyle(color: WorkspaceTheme.muted),
              ),
            ),
          const SizedBox(height: 20),
          if (page == 'Jobs')
            _section(
              'Fabric programme',
              (record['programme'] as List? ?? [])
                  .map(
                    (r) => _row(
                      r['fabric'].toString(),
                      '${r['colour'] ?? 'Natural'} · ${knittingDiameterTitle(r)} dia / ${r['gauge'] ?? '—'} G',
                      '${r['target_kg']} kg',
                    ),
                  )
                  .toList(),
              art: ArtObject.fabric,
            ),
        ],
        if (page != 'Jobs' || record == null)
          LayoutBuilder(
            builder: (context, bounds) {
              final input = TextField(
                key: ValueKey('$page-${record?['name']}'),
                controller: searchField,
                decoration: InputDecoration(
                  labelText: snapshot.paginated
                      ? (page == 'Jobs'
                            ? 'Search all jobs'
                            : 'Search all records')
                      : (page == 'Jobs'
                            ? 'Filter loaded jobs'
                            : 'Filter loaded records'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: onQuery,
              );
              if (page != 'Jobs') return input;
              final find = OutlinedButton(
                onPressed: onFind,
                child: const Text('Find any job'),
              );
              return bounds.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        input,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerLeft, child: find),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 8),
                        find,
                      ],
                    );
            },
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
        if (record == null &&
            page == 'Jobs' &&
            api != null &&
            snapshot.paginated &&
            onJobFilters != null) ...[
          const SizedBox(height: 12),
          _JobRegisterFilters(
            key: ValueKey((workspace.company, workspace.accessFingerprint)),
            api: api!,
            company: snapshot.company,
            customer: jobCustomer,
            fromDate: jobFromDate,
            toDate: jobToDate,
            onApply: onJobFilters!,
          ),
        ],
        if (originalProgramme && workspace.allows('lifecycle')) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: null,
              child: Text('Revise programme'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 12),
            child: Text(
              'Original programme changes are not available. You can revise the rate.',
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in visibleActions)
                OutlinedButton.icon(
                  onPressed: () => onAction(a),
                  icon: Icon(a.icon, size: 17),
                  label: Text(a.title),
                ),
              if (remainingActions.any((a) => !correction(a)))
                menu(
                  jobPage
                      ? 'More job entries'
                      : page == 'Jobs'
                      ? 'Job actions'
                      : 'More entries',
                  remainingActions.where((a) => !correction(a)),
                  Icons.add,
                ),
              if (remainingActions.any(correction))
                menu(
                  'Corrections & revisions',
                  remainingActions.where(correction),
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
        key: PageStorageKey((snapshot.company, page, record?['name'])),
        slivers: [
          SliverToBoxAdapter(child: main),
          if (page == 'Jobs' && record == null)
            _register(
              'jobs',
              (records, controls, loading) => SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(child: controls),
                  MillJobRegister(
                    sliverWidth: bounds.maxWidth,
                    jobs: records,
                    onJob: onJob,
                    onJobFromRow: onJobFromRow,
                    showOutput: workspace.allows('production'),
                    title: snapshot.paginated ? 'Jobs' : 'Recent jobs',
                    caption: snapshot.paginated
                        ? 'All company jobs · latest order dates first'
                        : '${jobs.length} of ${snapshot.rows('jobs').length} recent jobs',
                    empty: loading
                        ? 'Loading jobs…'
                        : query.trim().isNotEmpty || queueFilter != null
                        ? 'No jobs match this view. Change the search or status filter.'
                        : workspace.allows('new_job') &&
                              workspace.state == 'Active'
                        ? 'No jobs yet. Choose New job to enter a customer and fabric programme.'
                        : 'Jobs appear here when a programme is recorded for this company.',
                  ),
                ],
              ),
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
    Widget rollRow(Map<String, dynamic> r) {
      final action =
          page == 'Quality' &&
              const {
                'Awaiting QC',
                'On Hold',
                'Rework',
                'Rejected',
                'Released',
              }.contains(r['state'])
          ? 'quality'
          : page == 'Delivery' && r['state'] == 'Released'
          ? 'deliver'
          : null;
      final spec = knitActions.where((a) => a.id == action).firstOrNull;
      final actionable =
          spec != null &&
          spec.availableIn(workspace) &&
          selected?['status'] != 'Completed' &&
          onRoll != null &&
          r['job'] is String;
      return _row(
        r['name'].toString(),
        '${r['job']} · ${r['machine'] ?? 'Manual'} · ${r['state']}',
        '${r['weight_kg']} kg',
        onTap: actionable ? () => onRoll!(spec, r) : null,
        actionLabel: spec?.title,
        actionIcon: spec?.icon,
      );
    }

    return [
      if (page == 'Yarn')
        _registerSection(
          'lots',
          'YARN LOTS',
          (r) => _row(
            r['name'].toString(),
            '${r['item']} · ${r['material_owner']} · ${r['party'] ?? workspace.company}',
            _allocation(r),
          ),
        ),
      if (page == 'Planning')
        _registerSection(
          'plans',
          'MACHINE QUEUE',
          (r) => _row(
            r['machine'].toString(),
            '${r['job']}\n${r['starts_at']} → ${r['ends_at']}',
            '${r['quantity_kg']} kg',
          ),
        ),
      if (['Production', 'Quality', 'Delivery'].contains(page))
        _registerSection('rolls', 'ROLLS & QUALITY', rollRow),
      if (['Production', 'Quality', 'Delivery'].contains(page))
        _registerSection(
          'batches',
          'FABRIC BATCHES',
          (r) => _row(
            r['source_reference']?.toString().isNotEmpty == true
                ? r['source_reference'].toString()
                : r['name'].toString(),
            '${r['job']} · ${r['state']}\n${r['captured_at'] ?? ''}',
            '${r['quantity_kg']} kg · ${r['rolls']} rolls',
          ),
        ),
      if (page == 'Factory') ...[
        if (onMasterCategory != null && api != null && snapshot.paginated)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 300,
              child: KeyedSubtree(
                key: ValueKey((snapshot.company, masterCategory)),
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('factory-master-category'),
                  initialValue: masterCategory ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Master category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All categories'),
                    ),
                    for (final category in _masterCategories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      onMasterCategory!(value == '' ? null : value),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _registerSection(
          'masters',
          'INDUSTRY MASTERS',
          (r) => _row(
            r['title'].toString(),
            r['category'].toString(),
            r['enabled'] == 1 ? 'Active' : 'Inactive',
            onTap: onMaster == null ? null : () => onMaster!(r),
          ),
        ),
        _registerSection(
          'machines',
          'MACHINES',
          (r) => _row(
            r['title'].toString(),
            '${r['dia']} dia · ${r['gauge']} gauge · ${r['knit_type']}',
            '${r['capacity_kg']} kg / 8h',
          ),
        ),
        _registerSection(
          'components',
          'COMPONENT LIFE',
          (r) => _row(
            '${r['component_type']} · ${r['machine']}',
            'Run ${r['run_kg']} / ${r['boundary_kg']} kg',
            '${r['remaining_kg']} kg left',
          ),
        ),
      ],
      if (page == 'Factory' || page == 'Subcontracting')
        _registerSection(
          'subcontracts',
          'SUBCONTRACTS',
          (r) => _row(
            r['name'].toString(),
            '${r['supplier']} · ${r['status']}',
            '${r['target_kg']} kg',
            onTap: onSubcontract != null
                ? () => onSubcontract!(r)
                : r['purchase_order'] != null
                ? () =>
                      onSource('Purchase Order', r['purchase_order'].toString())
                : null,
          ),
        ),
      if (page == 'Factory') ...[
        _registerSection(
          'holidays',
          'FACTORY CALENDAR',
          (r) => _row(
            r['date'].toString(),
            r['description']?.toString() ?? 'Holiday',
            r['machine']?.toString() ?? 'Whole factory',
          ),
        ),
      ],
      if (queueFilter == null &&
              ['Billing', 'Delivery', 'Production', 'Quality'].contains(page) ||
          page == 'Jobs' && selected != null)
        _registerSection(
          'events',
          page == 'Billing' ? 'Job billing activity' : 'Posted activity',
          (r) {
            final result = r['result'] as Map? ?? {};
            final billingVoucher = page == 'Billing' ? result['voucher'] : null;
            return _row(
              switch (r['kind']) {
                'invoice' => 'Sales invoice',
                'credit_invoice' => 'Credit note',
                'bill_yarn' => 'Yarn purchase bill',
                'subcontract_bill' => 'Subcontract bill',
                'migration_delivery_reference' =>
                  'Original delivery available for billing',
                'migration_billing_initialization' =>
                  'Original delivery totals',
                'migration_stock_initialization' => 'Imported stock opening',
                _ => r['kind'].toString().replaceAll('_', ' '),
              },
              '${billingVoucher ?? result['source_reference'] ?? r['name']} · ${result['original_date'] ?? r['occurred_at']}\n${result['quantity_kg'] != null ? '${result['quantity_kg']} kg' : ''}${r['cancelled'] == 1 ? ' · Cancelled' : ''}',
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
          },
        ),
      if (page == 'Billing')
        _registerSection(
          'rates',
          'AGREED RATES',
          (r) => _row(
            '${knittingCustomerTitle(r)} · ${r['fabric']}',
            '${r['yarn_count'] ?? ''} / ${r['gauge'] ?? ''} · ${r['effective_from']}',
            '${r['rate']} / kg',
          ),
        ),
    ];
  }

  Widget _register(
    String key,
    Widget Function(List<Map<String, dynamic>>, Widget, bool) builder,
  ) {
    if (api == null || !snapshot.paginated) {
      return builder(rows(key), const SizedBox.shrink(), false);
    }
    return KnittingRegisterPage(
      key: ValueKey('register-$key'),
      api: api!,
      snapshot: snapshot,
      collection: key,
      customer: key == 'jobs' ? (jobCustomer?['name'] as String?) : null,
      category: key == 'masters' ? masterCategory : null,
      fromDate: key == 'jobs' ? jobFromDate : null,
      toDate: key == 'jobs' ? jobToDate : null,
      job: selected?['name'] as String?,
      query: query,
      state: key == 'events' && page == 'Billing'
          ? 'Billing'
          : const {'jobs', 'rolls', 'plans'}.contains(key)
          ? queueFilter
          : null,
      start: pageStarts[key] ?? 0,
      onPage: (start) => onPage?.call(key, start),
      builder: builder,
    );
  }

  Widget _registerSection(
    String key,
    String title,
    Widget Function(Map<String, dynamic>) row,
  ) => _register(
    key,
    (records, controls, loading) => _section(
      title,
      records.map(row).toList(),
      controls: controls,
      loading: loading,
    ),
  );

  String _allocation(Map r) {
    if (selected == null) {
      return '${r['general_kg'] ?? '0.000'} kg · ${r['general_units'] ?? '0'} units general';
    }
    final a = (r['allocations'] as List? ?? []).where(
      (a) => a['job'] == selected!['name'],
    );
    return '${a.isEmpty ? '0.000' : a.first['quantity_kg']} kg · ${a.isEmpty ? '0' : a.first['units'] ?? '0'} units allocated';
  }

  Widget _section(
    String title,
    List<Widget> children, {
    ArtObject? art,
    Widget? controls,
    bool loading = false,
  }) => Padding(
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
          ?controls,
          if (children.isEmpty && !loading)
            _empty(
              query.trim().isNotEmpty || queueFilter != null
                  ? 'No records match the current filter.'
                  : switch (title) {
                      'YARN LOTS' =>
                        'Yarn lots appear after a material receipt.',
                      'MACHINE QUEUE' => 'Machine allocations appear here after a programme is scheduled.',
                      'ROLLS & QUALITY' => 'Recording production or receiving subcontract fabric creates rolls for inspection.',
                      'Posted activity' => 'Confirmed entries appear here with their source records.',
                      'Job billing activity' => 'Bills, credits and original delivery references appear here.',
                      _ => 'Nothing recorded here yet.',
                    },
            )
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
    String? actionLabel,
    IconData? actionIcon,
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
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(amount),
                      if (onTap != null)
                        Icon(
                          actionIcon ?? Icons.open_in_new,
                          size: 16,
                          semanticLabel: actionLabel ?? 'Open source document',
                        ),
                    ],
                  ),
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
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        actionIcon ?? Icons.open_in_new,
                        size: 16,
                        semanticLabel: actionLabel ?? 'Open source document',
                      ),
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

Future<bool> _confirmDiscardSetup(BuildContext context) async {
  return await showDialog<bool>(
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
      ) ??
      false;
}

class _Setup extends StatefulWidget {
  const _Setup({
    required this.api,
    required this.workspace,
    required this.onSaved,
    this.onDirty,
    this.parentHandlesBack = false,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final ValueChanged<WorkspaceContext> onSaved;
  final ValueChanged<bool>? onDirty;
  final bool parentHandlesBack;
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
    final discard = await _confirmDiscardSetup(context);
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
      canPop: widget.parentHandlesBack || !dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !widget.parentHandlesBack) leaveSetup();
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
                  label: Text(choice ? 'Knitting' : 'General ERP'),
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
                                      : RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                                            .hasMatch(v ?? '')
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
