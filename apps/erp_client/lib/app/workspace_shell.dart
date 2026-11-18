import '../core/models/workspace_edition.dart';
import '../features/overview/data/erp_overview_repository.dart';
import '../features/overview/presentation/overview_view_model.dart';
import '../features/workspace/data/erp_workspace_repository.dart';
import '../features/workspace/presentation/workspace_view_model.dart';
import '../pending_operations.dart';
import '../retained_load.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../core/ui/reduce_transparency.dart';
import '../document_editor.dart';
import '../native_catalog.dart';
import '../erp_api.dart';
import '../erp_models.dart';
import '../module_browser.dart';
import '../payment_reconciliation.dart';
import '../bank_statement_matching.dart';
import '../pos_checkout.dart';
import '../overview.dart';
import '../invoice_hub.dart';
import '../invoice_composer.dart';
import '../invoice_preview.dart';
import '../imported_history.dart';
import '../sign_in.dart';
import '../local_workspace.dart';
import '../team_access.dart';
import '../session_recovery.dart';
import '../widgets.dart';
import '../workspace_picker.dart';
import '../workspace_context.dart';
import '../knitting_screen.dart';
import '../ui/access_gate.dart';
import '../ui/workspace_ui.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'Manrope': 'Manrope-OFL.txt',
      'Barlow Condensed': 'BarlowCondensed-OFL.txt',
      'ERP Workspace': 'GPL-3.0.txt',
      'Flutter': 'Flutter-BSD.txt',
      'Frappe Framework': 'Frappe-MIT.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}'));
    }
  });
  runApp(const ErpWorkspaceApp());
}

class ErpWorkspaceApp extends StatelessWidget {
  const ErpWorkspaceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: knittingCustomerBuild ? 'Knitting Workspace' : 'ERP Workspace',
    debugShowCheckedModeBanner: false,
    theme: WorkspaceTheme.theme,
    builder: (_, child) =>
        WorkspaceMotionScope(child: ReduceTransparencyScope(child: child!)),
    home: WorkspaceShell(
      openLocal: LocalWorkspace.enabled ? LocalWorkspace.open : null,
      openLocalCompany: LocalWorkspace.enabled
          ? (name) => LocalWorkspace.open(company: name)
          : null,
      openLocalProfile: LocalWorkspace.enabled
          ? (id, company) =>
                LocalWorkspace.open(workspaceId: id, company: company)
          : null,
    ),
  );
}

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    this.connect = ErpApi.new,
    this.openLocal,
    this.openLocalCompany,
    this.openLocalProfile,
  });
  final Future<LocalWorkspace> Function()? openLocal;
  final Future<LocalWorkspace> Function(String)? openLocalCompany;
  final Future<LocalWorkspace> Function(String, String?)? openLocalProfile;
  final ErpApi Function(Uri) connect;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  ErpApi? _api;
  Future<ErpSnapshot>? _snapshot;
  OverviewViewModel? _overviewModel;
  ReportingPeriod _period = ReportingPeriod.month;
  ErpModule? _module;
  bool _generalInMill = false;
  bool _unpaidOnly = false;
  bool get _atMill =>
      _workspace?.knittingOnly == true ||
      _workspace?.enabled == true && !_generalInMill;
  int _revision = 0;
  WorkspaceViewModel? _workspaceModel;
  WorkspaceContext? get _workspace => _workspaceModel?.context;
  set _workspace(WorkspaceContext? value) {
    if (value == null) {
      _workspaceModel?.clear();
    } else {
      _workspaceModel!.adopt(value);
    }
  }

  int _connectionAttempt = 0;
  late ErpApi Function() _entryConnect;
  late Future<void> Function(String, String) _entrySignIn;
  bool _currentAttempt(int at) => mounted && at == _connectionAttempt;
  void _configureEntry() {
    final factory = widget.connect;
    _entryConnect = () => factory(ErpApi.serviceOrigin);
    _entrySignIn = (username, password) => _signIn(factory, username, password);
  }

  void _resetConnection() {
    _connectionAttempt++;
    _workspaceModel?.dispose();
    _workspaceModel = null;
    _api?.close();
    _api = null;
    _clearOverview();
    _module = null;
    _generalInMill = false;
    _unpaidOnly = false;
    _localBusy = false;
    _localError = null;
    _localCompanies = const [];
    _localProfiles = const [];
    _localWorkspaceId = null;
  }

  @override
  void didUpdateWidget(covariant WorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connect != widget.connect) {
      _configureEntry();
      if (widget.openLocal == null) _resetConnection();
    }
    if (oldWidget.openLocal != widget.openLocal) {
      _resetConnection();
      if (widget.openLocal != null) {
        final opener = widget.openLocal;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.openLocal == opener) _openLocal();
        });
      }
    }
  }

  @override
  void dispose() {
    _connectionAttempt++;
    _overviewModel?.dispose();
    _workspaceModel?.dispose();
    _api?.close();
    super.dispose();
  }

  bool _localBusy = false;
  String? _localError;
  List<Map<String, String>> _localCompanies = const [];
  List<Map<String, String>> _localProfiles = const [];
  String? _localWorkspaceId;

  @override
  void initState() {
    super.initState();
    _configureEntry();
    if (widget.openLocal != null) _openLocal();
  }

  Future<void> _openLocal([String? company, String? workspaceId]) async {
    if (_localBusy) return;
    final at = ++_connectionAttempt;
    final profile = workspaceId ?? _localWorkspaceId;
    final profileOpener = widget.openLocalProfile;
    final companyOpener = widget.openLocalCompany;
    final defaultOpener = widget.openLocal;
    final Object? opener = profile != null && profileOpener != null
        ? profileOpener
        : company != null
        ? companyOpener
        : defaultOpener;
    bool sameOpener() =>
        opener ==
        (profile != null && widget.openLocalProfile != null
            ? widget.openLocalProfile
            : company != null
            ? widget.openLocalCompany
            : widget.openLocal);
    setState(() {
      _localBusy = true;
      _localError = null;
    });
    ErpApi? api;
    WorkspaceViewModel? candidate;
    try {
      final local = profile != null && profileOpener != null
          ? await profileOpener(profile, company)
          : company == null
          ? await defaultOpener!()
          : await companyOpener!(company);
      api = local.api;
      if (!_currentAttempt(at) || !sameOpener()) {
        api.close();
        return;
      }
      candidate = WorkspaceViewModel(
        ErpWorkspaceRepository(api, local: local, requestedCompany: company),
      );
      final workspace = await candidate.load(company: local.company);
      if (!_currentAttempt(at) || !sameOpener() || workspace == null) {
        candidate.dispose();
        api.close();
        return;
      }
      final previous = _api, previousModel = _workspaceModel;
      setState(() {
        _api = api;
        _workspaceModel = candidate;
        _localCompanies = local.companies;
        _localProfiles = local.profiles;
        _localWorkspaceId = local.workspaceId;
        _generalInMill = false;
        _module = null;
        _unpaidOnly = false;
        _revision++;
        _localBusy = false;
        _snapshot = _overviewFor(api!, workspace);
      });
      previousModel?.dispose();
      if (previous != null && !identical(previous, api)) previous.close();
    } catch (error) {
      candidate?.dispose();
      api?.close();
      if (mounted && _currentAttempt(at)) {
        setState(() {
          _localBusy = false;
          _localError = error is ErpException
              ? error.message
              : 'The local workspace could not be opened.';
        });
        if (_api != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_localError!)));
        }
      }
    } finally {
      if (_currentAttempt(at) && _localBusy) setState(() => _localBusy = false);
    }
  }

  Future<void> _signIn(
    ErpApi Function(Uri) factory,
    String username,
    String password,
  ) async {
    final at = ++_connectionAttempt;
    final api = factory(ErpApi.serviceOrigin);
    WorkspaceViewModel? candidate;
    try {
      await signInWithVerification(context, api, username, password);
      if (!_currentAttempt(at) || widget.connect != factory) {
        api.close();
        return;
      }
      candidate = WorkspaceViewModel(ErpWorkspaceRepository(api));
      final workspace = await candidate.load();
      if (!_currentAttempt(at) ||
          widget.connect != factory ||
          workspace == null) {
        candidate.dispose();
        api.close();
        return;
      }
      api.onSessionExpired = () => _recoverSession(api);
      final previous = _api, previousModel = _workspaceModel;
      setState(() {
        _api = api;
        _workspaceModel = candidate;
        _generalInMill = false;
        _module = null;
        _snapshot = _overviewFor(api, workspace);
      });
      previousModel?.dispose();
      if (previous != null && !identical(previous, api)) previous.close();
    } catch (_) {
      candidate?.dispose();
      api.close();
      rethrow;
    }
  }

  Future<bool> _recoverSession(ErpApi api) async {
    if (!mounted || !identical(_api, api)) return false;
    final restored = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SessionRecoveryDialog(api: api),
    );
    // AccessGate refreshes the selected company and each open route when the
    // session is restored. Its retry screen keeps drafts open if that read fails.
    if (restored == true) return mounted && identical(_api, api);
    if (mounted && identical(_api, api)) {
      api.onSessionExpired = null;
      api.close();
      setState(() {
        _api = null;
        _clearOverview();
      });
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceShell(connect: widget.connect),
        ),
        (_) => false,
      );
    }
    return false;
  }

  Future<T> _guard<T>(ErpApi api, Future<T> future) async {
    try {
      return await future;
    } on ErpException catch (e) {
      if (e.sessionExpired && mounted && identical(_api, api)) {
        api.close();
        setState(() {
          _api = null;
          _clearOverview();
        });
      }
      rethrow;
    }
  }

  void _clearOverview() {
    _overviewModel?.dispose();
    _overviewModel = null;
    _snapshot = null;
  }

  Future<ErpSnapshot>? _overviewFor(ErpApi api, WorkspaceContext workspace) {
    _overviewModel?.dispose();
    _overviewModel = null;
    if (workspace.company == null ||
        workspace.cashierHome ||
        workspace.knittingOnly ||
        (workspace.enabled && !_generalInMill) ||
        workspace.needsIndustrySelection) {
      return null;
    }
    final model = OverviewViewModel(
      ErpOverviewRepository(api: api, company: workspace.company!),
      period: _period,
    );
    _overviewModel = model;
    return _guard(api, model.result);
  }

  void _applyCompany(WorkspaceContext value, {bool keepGeneral = false}) {
    final api = _api;
    if (!mounted || api == null) return;
    setState(() {
      _generalInMill = keepGeneral && value.enabled && !value.knittingOnly;
      _workspace = value;
      _module = null;
      _revision++;
      _snapshot = _overviewFor(api, value);
    });
  }

  void _refresh() {
    final api = _api;
    final workspace = _workspace;
    if (api == null ||
        workspace == null ||
        _atMill ||
        workspace.needsIndustrySelection) {
      return;
    }
    setState(() {
      _revision++;
      _snapshot = _overviewFor(api, workspace);
    });
  }

  Future<void> _signOut() async {
    final api = _api;
    if (api == null) return;
    _connectionAttempt++;
    setState(() {
      _api = null;
      _clearOverview();
      _module = null;
      _workspace = null;
    });
    try {
      await api.signOut();
    } catch (_) {
      /* Local sign-out remains effective if the service is unavailable. */
    } finally {
      api.close();
    }
  }

  Future<void> _checkCompanyAccess() async {
    final api = _api;
    if (api == null) return;
    try {
      final workspace = await _workspaceModel!.load();
      if (!mounted || !identical(api, _api) || workspace == null) return;
      _applyCompany(workspace);
      if (workspace.company == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account is still waiting for company access.'),
          ),
        );
      }
    } catch (e) {
      if (mounted && identical(api, _api)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<WorkspaceContext> _currentCompany(ErpApi api) async {
    final model = _workspaceModel;
    if (!identical(api, _api) || model == null) {
      throw const ErpException('The workspace changed. Try again.');
    }
    final value = await model.current(_workspace?.company);
    if (value == null ||
        !mounted ||
        !identical(api, _api) ||
        !identical(model, _workspaceModel)) {
      throw const ErpException('The workspace changed. Try again.');
    }
    return value;
  }

  Future<void> _company() async {
    final api = _api;
    if (api == null || _localBusy || _workspaceModel?.selecting == true) return;
    try {
      final fresh = await _currentCompany(api);
      if (!mounted || !identical(_api, api)) return;
      final keepGeneral =
          !_atMill && _workspace?.needsIndustrySelection == false;
      if (fresh.company != _workspace?.company) {
        _applyCompany(fresh, keepGeneral: keepGeneral);
      } else {
        _workspaceModel!.adopt(fresh);
      }
      if (fresh.companies.isEmpty) return;
      final accountAt = api.account, accessAt = api.accessRevision;
      var chooseWorkspace = false;
      final name = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Choose company')),
              IconButton(
                tooltip: 'Close company selector',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          children: [
            for (final row
                in _localWorkspaceId == null &&
                        widget.openLocalCompany != null &&
                        _localCompanies.isNotEmpty
                    ? _localCompanies
                    : fresh.companies.where(
                        (row) =>
                            !knittingCustomerBuild ||
                            row['name'] == fresh.company,
                      ))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, row['name'] as String),
                child: Semantics(
                  selected: row['name'] == fresh.company,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.business_outlined, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row['name'] as String),
                              if (row['industry'] != null)
                                Text(
                                  row['industry'] == 'knitting'
                                      ? 'Knitting'
                                      : 'General ERP',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: WorkspaceTheme.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (row['name'] == fresh.company)
                          const Icon(Icons.check_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            if (_generalInMill && fresh.enabled)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(c);
                  _backToMill();
                },
                child: const Text('Open knitting workspace'),
              ),
            if (_localProfiles.length > 1 &&
                widget.openLocalProfile != null) ...[
              const Divider(),
              SimpleDialogOption(
                onPressed: () {
                  chooseWorkspace = true;
                  Navigator.pop(c);
                },
                child: const Text('Switch workspace'),
              ),
            ],
          ],
        ),
      );
      if (chooseWorkspace && mounted && identical(api, _api)) {
        await _chooseLocalWorkspace();
        return;
      }
      if (name == null ||
          !mounted ||
          !identical(api, _api) ||
          api.account != accountAt ||
          api.accessRevision != accessAt ||
          !api.accessReady) {
        return;
      }
      if (name == fresh.company && name == _workspace?.company) {
        // Reselecting the active company does not change the saved default.
        // A late redundant selection would reset a module already opened.
        return;
      }
      if ((_localWorkspaceId != null && widget.openLocalProfile != null) ||
          (widget.openLocalCompany != null && _localCompanies.isNotEmpty)) {
        await _openLocal(name);
        return;
      }
      final w = await _workspaceModel!.select(name);
      if (w != null && mounted && identical(api, _api)) {
        _applyCompany(w, keepGeneral: keepGeneral);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _chooseLocalWorkspace() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose workspace'),
        children: [
          for (final profile in _localProfiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, profile['id']),
              child: ListTile(
                leading: const Icon(Icons.workspaces_outlined),
                title: Text(profile['label']!),
                trailing: profile['id'] == _localWorkspaceId
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (mounted && selected != null && selected != _localWorkspaceId) {
      await _openLocal(null, selected);
    }
  }

  Future<void> _industrySetup() async {
    final api = _api;
    final workspace = _workspace;
    if (api == null || workspace == null) return;
    final updated = await Navigator.push<WorkspaceContext>(
      context,
      MaterialPageRoute(
        builder: (routeContext) => IndustrySetupScreen(
          api: api,
          workspace: workspace,
          onSaved: (value) => Navigator.of(routeContext).pop(value),
        ),
      ),
    );
    if (updated != null && mounted && identical(api, _api)) {
      _applyCompany(updated, keepGeneral: true);
    }
  }

  void _licenses() => showLicensePage(
    context: context,
    applicationName: 'ERP Workspace',
    applicationVersion: '0.2.0',
    applicationLegalese:
        'Independent open source client, powered by ERPNext and Frappe.',
  );
  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const ErpException('The browser could not be opened.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the browser. Open ERPNext from your usual browser.',
            ),
          ),
        );
      }
    }
  }

  void _showGeneral([ErpModule? module]) {
    final workspace = _workspace;
    final api = _api;
    if (workspace == null || api == null || workspace.knittingOnly) return;
    setState(() {
      _generalInMill = true;
      _unpaidOnly = false;
      _module = module;
      _snapshot = _overviewFor(api, workspace);
    });
  }

  void _backToMill() => setState(() {
    _generalInMill = false;
    _module = null;
    _clearOverview();
  });

  void _select(ErpModule? module, {bool unpaidOnly = false}) {
    if (_workspace?.knittingOnly == true) return;
    setState(() {
      _module = module;
      _unpaidOnly = unpaidOnly && module == ErpModule.accounts;
    });
  }

  Future<void> _moduleMenu() async {
    if (_workspace?.knittingOnly == true) return;
    final snapshot = _snapshot;
    final invokingFocus = FocusManager.instance.primaryFocus;
    var navigated = false;
    if (snapshot == null) return;
    ErpSnapshot? data;
    try {
      data = await snapshot;
    } on ErpException {
      // The catalogue remains independently available if the dashboard failed.
    }
    if (!mounted || _api == null || !identical(snapshot, _snapshot)) return;
    await showWorkspacePicker(
      context,
      (module) {
        navigated = true;
        _select(module);
      },
      onAll: () {
        navigated = true;
        _catalog();
      },
      selected: _module,
      available: ErpModule.values.where((m) => data?.count(m) != null),
    );
    if (mounted &&
        !navigated &&
        invokingFocus?.context != null &&
        invokingFocus!.canRequestFocus) {
      invokingFocus.requestFocus();
    }
  }

  Future<void> _openReconciliation(
    ErpApi api,
    String company, {
    required bool bank,
  }) async {
    final workspace = _workspace;
    if (!identical(api, _api) ||
        workspace?.company != company ||
        !(bank
            ? workspace!.canMatchBankStatements
            : workspace!.canReconcilePayments)) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => bank
            ? BankStatementMatchingScreen(api: api, company: company)
            : PaymentReconciliationScreen(api: api, company: company),
      ),
    );
    if (mounted && identical(_api, api)) _refresh();
  }

  bool get _canOpenInvoices =>
      _workspace?.readableRecords.contains('Sales Invoice') == true;
  Future<void> _openImportedHistory({String? family}) async {
    final api = _api;
    final company = _workspace?.company;
    if (api == null ||
        company == null ||
        _workspace?.canReadImportedHistory != true) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportedHistoryScreen(
          api: api,
          company: company,
          initialFamily: family,
        ),
      ),
    );
  }

  bool get _canRecoverOperations {
    final company = _workspace?.company;
    return company != null &&
        _workspace?.cashierHome != true &&
        _api?.supportsOperationRecovery(company) == true;
  }

  Future<void> _openPendingOperations() async {
    final api = _api;
    final company = _workspace?.company;
    if (api == null || company == null || !_canRecoverOperations) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PendingOperationsScreen(api: api, company: company),
      ),
    );
  }

  Future<void> _openInvoices() async {
    final api = _api;
    final workspace = _workspace;
    final company = workspace?.company;
    if (api == null || company == null || !_canOpenInvoices) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceHub(
          api: api,
          company: company,
          canCreate: workspace!.creatableRecords.contains('Sales Invoice'),
          onImportedHistory: workspace.canReadImportedHistory
              ? () => _openImportedHistory(family: 'invoice')
              : null,
        ),
      ),
    );
    if (mounted && identical(api, _api)) _refresh();
  }

  Future<void> _previewMillInvoice(String company, String name) async {
    final api = _api;
    if (api == null ||
        !api.accessReady ||
        _workspace?.company != company ||
        !_canOpenInvoices)
      return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InvoicePreviewScreen(api: api, company: company, invoice: name),
      ),
    );
  }

  Future<void> _edit(String doctype, {String? name}) async {
    final api = _api;
    final company = _workspace?.company;
    if (api == null) return;
    if (doctype == 'Sales Invoice' && name == null && company != null) {
      await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceComposer(api: api, company: company),
        ),
      );
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditor(
            api: api,
            doctype: doctype,
            name: name,
            company: company,
          ),
        ),
      );
    }
    if (mounted && identical(_api, api)) _refresh();
  }

  Future<void> _catalog({bool create = false}) async {
    final api = _api;
    final workspace = _workspace;
    if (api == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NativeCatalogScreen(
          api: api,
          company: workspace?.company,
          create: create,
          knittingOnly: workspace?.knittingOnly == true,
          onReconcile: workspace?.canReconcilePayments == true
              ? () => _openReconciliation(api, workspace!.company!, bank: false)
              : null,
          onBankMatch: workspace?.canMatchBankStatements == true
              ? () => _openReconciliation(api, workspace!.company!, bank: true)
              : null,
        ),
      ),
    );
    if (mounted && identical(_api, api)) _refresh();
  }

  void _settings() {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: WorkspaceTheme.canvas,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Display('Account and settings', size: 31),
                    ),
                    IconButton(
                      tooltip: 'Close settings',
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  _api?.userName ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _workspace?.company ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WorkspaceTheme.muted,
                  ),
                ),
                const SizedBox(height: 19),
                if (_canRecoverOperations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pending_actions_outlined),
                    title: const Text('Pending operations'),
                    subtitle: const Text(
                      'Check the outcome of interrupted saves',
                    ),
                    onTap: () {
                      Navigator.pop(c);
                      _openPendingOperations();
                    },
                  ),
                if (_workspace?.canManageTeam == true &&
                    _workspace?.company != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Team access'),
                    subtitle: const Text('Invite staff and manage invitations'),
                    onTap: () {
                      final api = _api!;
                      final company = _workspace!.company!;
                      Navigator.pop(c);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TeamAccessScreen(
                            api: api,
                            company: company,
                            knitting: _workspace!.enabled,
                          ),
                        ),
                      );
                    },
                  ),
                if (_workspace?.canOpenDesk == true &&
                    _workspace?.knittingOnly != true)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open original ERPNext'),
                    onTap: () {
                      Navigator.pop(c);
                      _open(_api!.baseUri.resolve('/desk'));
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open source licenses'),
                  onTap: () {
                    Navigator.pop(c);
                    _licenses();
                  },
                ),
                const SizedBox(height: 14),
                if (widget.openLocal == null)
                  Pill(
                    'Sign out',
                    icon: Icons.logout,
                    onPressed: () {
                      Navigator.pop(c);
                      _signOut();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    final phone = workspaceUsesPhoneNavigation(context);
    if (widget.openLocal != null && (api == null || _localBusy)) {
      return Scaffold(
        body: WorkspaceBackdrop(
          child: SafeArea(
            child: Center(
              child: _localBusy
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Opening your company…'),
                      ],
                    )
                  : MessagePanel(
                      title: 'Local workspace unavailable',
                      message:
                          '${_localError ?? "The workspace connection was interrupted."} Start the local service with the ERP Workspace launcher, then retry.',
                      action: _openLocal,
                      label: 'Retry connection',
                    ),
            ),
          ),
        ),
      );
    }
    if (api == null) {
      return SignInScreen(
        connect: _entryConnect,
        onSignIn: _entrySignIn,
        onLicenses: _licenses,
      );
    }
    return AccessGate(
      key: ValueKey((api, _workspace?.company)),
      api: api,
      revalidate: () async {
        final companyAtStart = _workspace?.company;
        final modelAtStart = _workspaceModel;
        final fresh = await _currentCompany(api);
        if (!mounted ||
            !identical(api, _api) ||
            !identical(modelAtStart, _workspaceModel) ||
            companyAtStart != _workspace?.company) {
          return;
        }
        _generalInMill =
            fresh.enabled &&
            !fresh.knittingOnly &&
            !_atMill &&
            _workspace?.needsIndustrySelection == false;
        final snapshot = _overviewFor(api, fresh);
        setState(() {
          _workspace = fresh;
          _module = null;
          _revision++;
          _snapshot = snapshot;
        });
        await snapshot;
      },
      child: _workspace!.company == null
          ? Scaffold(
              appBar: AppBar(
                title: const Text('ERP Workspace'),
                actions: [
                  TextButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
              body: WorkspaceBackdrop(
                child: Center(
                  child: MessagePanel(
                    title: 'No company assigned',
                    message:
                        'Ask your workspace manager to give ${api.account} access to a company. Once access is assigned, you can continue here.',
                    action: _checkCompanyAccess,
                    label: 'Check access',
                  ),
                ),
              ),
            )
          : !knittingCustomerBuild && _workspace!.cashierHome
          ? PosCheckoutScreen(
              api: api,
              company: _workspace!.company!,
              onAccount: _settings,
            )
          : _atMill
          ? KnittingScreen(
              key: ValueKey(_workspace!.company),
              api: api,
              workspace: _workspace!,
              onContextChanged: (value) {
                if (!mounted ||
                    !identical(api, _api) ||
                    _workspace?.company != value.company) {
                  return;
                }
                if (!value.enabled) {
                  _applyCompany(value);
                } else {
                  setState(() => _workspace = value);
                }
              },
              onCompany: _company,
              onRecords: _catalog,
              onGeneral: _workspace!.knittingOnly ? null : _showGeneral,
              onInvoices: _canOpenInvoices ? _openInvoices : null,
              onInvoicePreview: _canOpenInvoices ? _previewMillInvoice : null,
              invoiceWorkspace: _canOpenInvoices
                  ? (jobBilling, billFromDelivery, refreshBilling) =>
                        InvoiceHub(
                          api: api,
                          company: _workspace!.company!,
                          canCreate: _workspace!.creatableRecords.contains(
                            'Sales Invoice',
                          ),
                          jobBilling: jobBilling,
                          onBillFromDelivery: billFromDelivery,
                          onRefreshJobBilling: refreshBilling,
                          onImportedHistory: _workspace!.canReadImportedHistory
                              ? () => _openImportedHistory(family: 'invoice')
                              : null,
                        )
                  : null,
              onHistory: _workspace!.canReadImportedHistory
                  ? (family) => _openImportedHistory(family: family)
                  : null,
              onBusinessModule: _workspace!.knittingOnly ? null : _showGeneral,
              onAccount: _settings,
            )
          : _workspace!.needsIndustrySelection
          ? IndustrySetupScreen(
              key: ValueKey(_workspace!.company),
              api: api,
              workspace: _workspace!,
              onSaved: _applyCompany,
              onCompany: _company,
              onAccount: _settings,
            )
          : PopScope(
              canPop: _module == null && !_generalInMill,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_module != null) {
                  _select(null);
                } else if (_generalInMill) {
                  _backToMill();
                }
              },
              child: CallbackShortcuts(
                bindings: {
                  SingleActivator(
                    LogicalKeyboardKey.keyK,
                    meta: Theme.of(context).platform == TargetPlatform.macOS,
                    control: Theme.of(context).platform != TargetPlatform.macOS,
                  ): _moduleMenu,
                  SingleActivator(
                    LogicalKeyboardKey.keyR,
                    meta: Theme.of(context).platform == TargetPlatform.macOS,
                    control: Theme.of(context).platform != TargetPlatform.macOS,
                  ): _refresh,
                },
                child: Focus(
                  autofocus: true,
                  child: Scaffold(
                    bottomNavigationBar:
                        phone && MediaQuery.viewInsetsOf(context).bottom == 0
                        ? _phoneNavigation()
                        : null,
                    body: SafeArea(
                      child: RetainedFutureBuilder<ErpSnapshot>(
                        future: _snapshot,
                        scope: (
                          api,
                          api.account,
                          _workspace!.company,
                          api.accessRevision,
                          _period,
                        ),
                        builder: (context, state) {
                          final module = _module;
                          final unpaidOnly = _unpaidOnly;
                          final period = _period;
                          final data = state.data;
                          final overview = _overviewModel!;
                          return WorkspaceBackdrop(
                            child: Column(
                              children: [
                                _header(phone: phone),
                                RetainedLoadNotice(
                                  loading: state.loading && state.hasData,
                                  error: state.hasData ? state.error : null,
                                  onRetry: _refresh,
                                ),
                                Expanded(
                                  child: KeyedSubtree(
                                    key: ValueKey((
                                      api,
                                      api.account,
                                      _workspace!.company,
                                      api.accessRevision,
                                      _period,
                                    )),
                                    child: WorkspaceDestinationTransition(
                                      location: (module, unpaidOnly),
                                      child: state.loading && !state.hasData
                                          ? const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: WorkspaceTheme.ink,
                                              ),
                                            )
                                          : state.hasError && !state.hasData
                                          ? MessagePanel(
                                              title: 'Could not load this workspace',
                                              message: state.error.toString(),
                                              action: _refresh,
                                            )
                                          : module == null
                                          ? OverviewScreen(
                                              key: PageStorageKey((
                                                api,
                                                api.account,
                                                _workspace!.company,
                                                api.accessRevision,
                                                period,
                                              )),
                                              data: data!,
                                              showCompany: false,
                                              range: _period.range(
                                                DateTime.now(),
                                              ),
                                              onRecord: (r) => _edit(
                                                r.module.doctype,
                                                name: r.name,
                                              ),
                                              onModule: _select,
                                              onUnpaid: () => _select(
                                                ErpModule.accounts,
                                                unpaidOnly: true,
                                              ),
                                              onInvoices: _canOpenInvoices
                                                  ? _openInvoices
                                                  : null,
                                              onNew: () =>
                                                  _catalog(create: true),
                                            )
                                          : ModuleBrowser(
                                              key: ValueKey(
                                                '${module.name}-${period.name}-$unpaidOnly',
                                              ),
                                              refreshRevision: _revision,
                                              showCompany: false,
                                              scope: (
                                                api,
                                                api.account,
                                                _workspace!.company,
                                                api.accessRevision,
                                                period,
                                                unpaidOnly,
                                              ),
                                              module: module,
                                              company: data!.company,
                                              currency: data.currency,
                                              onInvoices:
                                                  _canOpenInvoices &&
                                                      (module ==
                                                              ErpModule
                                                                  .selling ||
                                                          module ==
                                                              ErpModule
                                                                  .accounts)
                                                  ? _openInvoices
                                                  : null,
                                              onImportedHistory:
                                                  _workspace!
                                                      .canReadImportedHistory
                                                  ? () => _openImportedHistory(
                                                      family:
                                                          module ==
                                                              ErpModule.accounts
                                                          ? 'voucher'
                                                          : null,
                                                    )
                                                  : null,
                                              onCheckout:
                                                  module == ErpModule.selling &&
                                                      _workspace!.canOperatePos
                                                  ? () async {
                                                      await Navigator.push(
                                                        context,
                                                        MaterialPageRoute<void>(
                                                          builder: (_) =>
                                                              PosCheckoutScreen(
                                                                api: api,
                                                                company: data
                                                                    .company,
                                                              ),
                                                        ),
                                                      );
                                                      if (mounted &&
                                                          identical(
                                                            _api,
                                                            api,
                                                          )) {
                                                        _refresh();
                                                      }
                                                    }
                                                  : null,
                                              onReconcile:
                                                  module ==
                                                          ErpModule.accounts &&
                                                      _workspace!
                                                          .canReconcilePayments
                                                  ? () => _openReconciliation(
                                                      api,
                                                      data.company,
                                                      bank: false,
                                                    )
                                                  : null,
                                              onBankMatch:
                                                  module ==
                                                          ErpModule.accounts &&
                                                      _workspace!
                                                          .canMatchBankStatements
                                                  ? () => _openReconciliation(
                                                      api,
                                                      data.company,
                                                      bank: true,
                                                    )
                                                  : null,
                                              onShowAll: unpaidOnly
                                                  ? () => _select(
                                                      ErpModule.accounts,
                                                    )
                                                  : null,
                                              loader: (query, start) => _guard(
                                                api,
                                                overview.records(
                                                  module,
                                                  query: query,
                                                  start: start,
                                                  unpaidOnly: unpaidOnly,
                                                ),
                                              ),
                                              onRecord: (r) => _edit(
                                                r.module.doctype,
                                                name: r.name,
                                              ),
                                              onCreate:
                                                  _workspace!.creatableRecords
                                                      .contains(module.doctype)
                                                  ? () => _edit(module.doctype)
                                                  : null,
                                              onBrowseAll: () => _catalog(),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _phoneNavigation() => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 4),
    child: Panel(
      frosted: true,
      radius: 16,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _moduleMenu,
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Workspaces'),
              ),
            ),
            const SizedBox(height: 24, child: VerticalDivider(width: 1)),
            Expanded(
              child: TextButton.icon(
                onPressed: _catalog,
                icon: const Icon(Icons.library_books_outlined),
                label: const Text('All modules'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header({required bool phone}) => LayoutBuilder(
    builder: (context, bounds) {
      final small =
          bounds.maxWidth < 1080 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      final company = TextButton.icon(
        style: phone
            ? TextButton.styleFrom(
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsetsDirectional.only(start: 6, end: 10),
              )
            : null,
        onPressed: _company,
        icon: const Icon(Icons.business_outlined, size: 17),
        label: Text(
          _workspace?.company ?? 'Select company',
          overflow: TextOverflow.ellipsis,
        ),
      );
      final command = Theme.of(context).platform == TargetPlatform.macOS
          ? '⌘'
          : 'Ctrl+';
      final navigation = Tooltip(
        message: 'Workspaces (${command}K)',
        child: TextButton.icon(
          onPressed: _moduleMenu,
          icon: Icon(
            _module == null ? Icons.grid_view_rounded : moduleIcon(_module!),
            size: 17,
          ),
          label: Text(
            _module?.label ?? 'Workspaces',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      final tools = PopupMenuButton<VoidCallback>(
        tooltip: 'Workspace options',
        icon: const Icon(Icons.more_horiz),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _refresh,
            child: Text(
              phone ? 'Refresh workspace' : 'Refresh workspace (${command}R)',
            ),
          ),
          if (phone && _workspace?.canReadImportedHistory == true)
            PopupMenuItem(
              value: () => _openImportedHistory(
                family: _module == ErpModule.accounts ? 'voucher' : null,
              ),
              child: const Text('Imported history'),
            ),
          if (_canRecoverOperations)
            PopupMenuItem(
              value: _openPendingOperations,
              child: const Text('Pending operations'),
            ),
          if (_workspace?.canConfigure == true)
            PopupMenuItem(
              value: _industrySetup,
              child: const Text('Industry setup'),
            ),
          PopupMenuItem(
            value: _settings,
            child: const Text('Account and settings'),
          ),
        ],
      );
      final overviewBack = IconButton(
        tooltip: 'Back to business overview',
        icon: const BackButtonIcon(),
        onPressed: () => _select(null),
      );
      if (phone) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              if (_module != null)
                overviewBack
              else if (_generalInMill)
                IconButton(
                  tooltip: 'Back to knitting workspace',
                  onPressed: _backToMill,
                  icon: const BackButtonIcon(),
                ),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: company),
              ),
              _periodPicker(),
              tools,
            ],
          ),
        );
      }
      final brand = TextButton.icon(
        onPressed: () => _select(null),
        icon: const Icon(Icons.dashboard_customize_rounded, size: 22),
        label: const Display('General ERP', size: 24),
      );
      final catalog = TextButton.icon(
        onPressed: _catalog,
        icon: const Icon(Icons.library_books_outlined, size: 17),
        label: const Text('All modules'),
      );
      final history = _workspace?.canReadImportedHistory == true
          ? TextButton.icon(
              onPressed: () => _openImportedHistory(
                family: _module == ErpModule.accounts ? 'voucher' : null,
              ),
              icon: const Icon(Icons.history_outlined, size: 17),
              label: const Text('Imported history'),
            )
          : null;
      final gutter = bounds.maxWidth >= 720 ? 24.0 : 14.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 2),
        child: Center(
          child: SizedBox(
            width: (bounds.maxWidth - 2 * gutter).clamp(0.0, 1580.0),
            child: Panel(
              frosted: true,
              radius: 16,
              padding: EdgeInsets.symmetric(
                horizontal: small ? 6 : 12,
                vertical: 3,
              ),
              child: small
                  ? Column(
                      children: [
                        Row(
                          children: [
                            if (_module != null) overviewBack,
                            Flexible(child: brand),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: company,
                              ),
                            ),
                            tools,
                          ],
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              navigation,
                              catalog,
                              ?history,
                              _periodPicker(),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_module != null) overviewBack,
                            brand,
                            const SizedBox(width: 10),
                            const SizedBox(
                              height: 18,
                              child: VerticalDivider(),
                            ),
                            navigation,
                            catalog,
                            ?history,
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: company,
                            ),
                            _periodPicker(),
                            tools,
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
  Widget _periodPicker() => PopupMenuButton<ReportingPeriod>(
    tooltip: 'Reporting period, ${_period.label}',
    initialValue: _period,
    onSelected: (p) {
      if (p == _period) return;
      setState(() => _period = p);
      _refresh();
    },
    itemBuilder: (_) => [
      for (final p in ReportingPeriod.values)
        PopupMenuItem(
          value: p,
          child: Text(p.label, style: const TextStyle(fontSize: 12)),
        ),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 13,
            color: WorkspaceTheme.muted,
          ),
          const SizedBox(width: 6),
          Text(
            _period.label,
            style: const TextStyle(fontSize: 12, color: WorkspaceTheme.ink),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 15),
        ],
      ),
    ),
  );
}
