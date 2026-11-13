import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'design.dart';
import 'document_editor.dart';
import 'native_catalog.dart';
import 'erp_api.dart';
import 'erp_models.dart';
import 'module_browser.dart';
import 'overview.dart';
import 'sign_in.dart';
import 'team_access.dart';
import 'session_recovery.dart';
import 'widgets.dart';
import 'workspace_picker.dart';
import 'workspace_context.dart';
import 'knitting_screen.dart';
import 'ui/access_gate.dart';

void main() {
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
    title: 'ERP Workspace',
    debugShowCheckedModeBanner: false,
    theme: WorkspaceTheme.theme,
    home: const WorkspaceShell(),
  );
}

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, this.connect = ErpApi.new});
  final ErpApi Function(Uri) connect;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  ErpApi? _api;
  Future<ErpSnapshot>? _snapshot;
  ReportingPeriod _period = ReportingPeriod.month;
  ErpModule? _module;
  bool _generalInMill = false;
  bool _unpaidOnly = false;
  bool get _atMill => _workspace?.enabled == true && !_generalInMill;
  int _revision = 0;
  WorkspaceContext? _workspace;
  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  ErpApi _connect() => widget.connect(ErpApi.serviceOrigin);

  Future<void> _signIn(String username, String password) async {
    final api = _connect();
    try {
      await signInWithVerification(context, api, username, password);
      if (!mounted) {
        api.close();
        return;
      }
      final workspace = await api.workspaceContext();
      if (!mounted) {
        api.close();
        return;
      }
      api.onSessionExpired = () => _recoverSession(api);
      setState(() {
        _api = api;
        _generalInMill = false;
        _workspace = workspace;
        _module = null;
        _snapshot = _overviewFor(api, workspace);
      });
    } catch (_) {
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
        _snapshot = null;
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
          _snapshot = null;
        });
      }
      rethrow;
    }
  }

  Future<ErpSnapshot>? _overviewFor(ErpApi api, WorkspaceContext workspace) =>
      workspace.company == null ||
          (workspace.enabled && !_generalInMill) ||
          workspace.needsIndustrySelection
      ? null
      : _guard(api, api.snapshot(_period, selectedCompany: workspace.company));

  void _applyCompany(WorkspaceContext value, {bool keepGeneral = false}) {
    final api = _api;
    if (!mounted || api == null) return;
    setState(() {
      _generalInMill = keepGeneral && value.enabled;
      _workspace = value;
      _module = null;
      _revision++;
      _snapshot = _overviewFor(api, value);
    });
  }

  void _refresh() {
    final api = _api;
    if (api == null || _atMill || _workspace?.needsIndustrySelection == true) {
      return;
    }
    setState(() {
      _revision++;
      _snapshot = _guard(
        api,
        api.snapshot(_period, selectedCompany: _workspace?.company),
      );
    });
  }

  Future<void> _signOut() async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _api = null;
      _snapshot = null;
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
      final workspace = await api.workspaceContext();
      if (!mounted || !identical(api, _api)) return;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<WorkspaceContext> _currentCompany(ErpApi api) async {
    try {
      return await api.workspaceContext(company: _workspace?.company);
    } on ErpException catch (error) {
      if (!error.permissionDenied) rethrow;
      return api.workspaceContext();
    }
  }

  Future<void> _company() async {
    final api = _api;
    if (api == null) return;
    try {
      final fresh = await _currentCompany(api);
      if (!mounted || !identical(_api, api)) return;
      final keepGeneral =
          !_atMill && _workspace?.needsIndustrySelection == false;
      if (fresh.company != _workspace?.company) {
        _applyCompany(fresh, keepGeneral: keepGeneral);
      }
      if (fresh.companies.isEmpty) return;
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
            for (final row in fresh.companies)
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
                        Expanded(child: Text(row['name'] as String)),
                        if (row['name'] == fresh.company)
                          const Icon(Icons.check_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      if (name == null || !mounted || !identical(api, _api)) return;
      if (name == fresh.company && name == _workspace?.company) {
        // Reselecting the active company does not change the saved default.
        // A late redundant selection would reset a module already opened.
        return;
      }
      final w = await api.selectCompany(name);
      if (mounted && identical(api, _api)) {
        _applyCompany(w, keepGeneral: keepGeneral);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
    if (workspace == null || api == null) return;
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
    _snapshot = null;
  });

  void _select(ErpModule? module, {bool unpaidOnly = false}) => setState(() {
    _module = module;
    _unpaidOnly = unpaidOnly && module == ErpModule.accounts;
  });
  Future<void> _moduleMenu() async {
    final snapshot = _snapshot;
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
      _select,
      onAll: _catalog,
      available: ErpModule.values.where((m) => data?.count(m) != null),
    );
  }

  Future<void> _edit(String doctype, {String? name}) async {
    final api = _api;
    if (api == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: doctype,
          name: name,
          company: _workspace?.company,
        ),
      ),
    );
    if (mounted && identical(_api, api)) _refresh();
  }

  Future<void> _catalog({bool create = false}) async {
    final api = _api;
    if (api == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NativeCatalogScreen(
          api: api,
          company: _workspace?.company,
          create: create,
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
    if (api == null) {
      return SignInScreen(
        connect: _connect,
        onSignIn: _signIn,
        onLicenses: _licenses,
      );
    }
    return AccessGate(
      api: api,
      revalidate: () async {
        final fresh = await _currentCompany(api);
        if (!mounted || !identical(api, _api)) return;
        _generalInMill =
            fresh.enabled &&
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
              onGeneral: _showGeneral,
              onBusinessModule: _showGeneral,
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
              canPop: _module == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && _module != null) _select(null);
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                      _moduleMenu,
                  const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
                      _refresh,
                },
                child: Focus(
                  autofocus: true,
                  child: Scaffold(
                    body: SafeArea(
                      child: FutureBuilder<ErpSnapshot>(
                        future: _snapshot,
                        builder: (context, state) {
                          final module = _module;
                          final unpaidOnly = _unpaidOnly;
                          final period = _period;
                          final data =
                              state.connectionState == ConnectionState.done
                              ? state.data
                              : null;
                          return WorkspaceBackdrop(
                            child: Column(
                              children: [
                                _header(),
                                Expanded(
                                  child: KeyedSubtree(
                                    key: ValueKey((
                                      _workspace!.company,
                                      api.accessRevision,
                                      _period,
                                      _revision,
                                    )),
                                    child: AnimatedSwitcher(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 190),
                                      switchInCurve: Curves.easeOutCubic,
                                      transitionBuilder: (panel, anim) =>
                                          FadeTransition(
                                            opacity: anim,
                                            child: SlideTransition(
                                              position: anim.drive(
                                                Tween(
                                                  begin: const Offset(.015, 0),
                                                  end: Offset.zero,
                                                ),
                                              ),
                                              child: panel,
                                            ),
                                          ),
                                      layoutBuilder: (current, previous) =>
                                          Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              for (final panel in [
                                                ...previous,
                                                ?current,
                                              ])
                                                KeyedSubtree(
                                                  key: panel.key,
                                                  child: ExcludeFocus(
                                                    excluding: panel != current,
                                                    child: ExcludeSemantics(
                                                      excluding:
                                                          panel != current,
                                                      child: IgnorePointer(
                                                        ignoring:
                                                            panel != current,
                                                        child: panel,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                      child:
                                          state.connectionState !=
                                              ConnectionState.done
                                          ? const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: WorkspaceTheme.ink,
                                              ),
                                            )
                                          : state.hasError
                                          ? MessagePanel(
                                              title:
                                                  'Could not load this workspace',
                                              message: state.error.toString(),
                                              action: _refresh,
                                            )
                                          : module == null
                                          ? OverviewScreen(
                                              data: data!,
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
                                              onNew: () =>
                                                  _catalog(create: true),
                                            )
                                          : ModuleBrowser(
                                              key: ValueKey(
                                                '${module.name}-${period.name}-$_revision-$unpaidOnly',
                                              ),
                                              module: module,
                                              company: data!.company,
                                              currency: data.currency,
                                              onShowAll: unpaidOnly
                                                  ? () => _select(
                                                      ErpModule.accounts,
                                                    )
                                                  : null,
                                              loader: (query, start) => _guard(
                                                api,
                                                api.records(
                                                  module,
                                                  company: data.company,
                                                  period: period,
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

  Widget _header() => LayoutBuilder(
    builder: (context, bounds) {
      final small =
          bounds.maxWidth < 1080 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      final company = TextButton.icon(
        onPressed: _company,
        icon: const Icon(Icons.business_outlined, size: 17),
        label: Text(
          _workspace?.company ?? 'Select company',
          overflow: TextOverflow.ellipsis,
        ),
      );
      final navigation = TextButton.icon(
        onPressed: _moduleMenu,
        icon: Icon(
          _module == null ? Icons.grid_view_rounded : moduleIcon(_module!),
          size: 17,
        ),
        label: Text(
          _module?.label ?? 'Workspaces',
          overflow: TextOverflow.ellipsis,
        ),
      );
      final tools = PopupMenuButton<VoidCallback>(
        tooltip: 'Workspace options',
        icon: const Icon(Icons.more_horiz),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _refresh,
            child: const Text('Refresh workspace'),
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
      final brand = TextButton.icon(
        onPressed: () => _select(null),
        icon: const Icon(Icons.dashboard_customize_rounded, size: 22),
        label: const Display('General ERP', size: 24),
      );
      final back = TextButton.icon(
        onPressed: _backToMill,
        icon: const Icon(Icons.factory_outlined, size: 18),
        label: const Text('Knitting workspace'),
      );
      final catalog = TextButton.icon(
        onPressed: _catalog,
        icon: const Icon(Icons.library_books_outlined, size: 17),
        label: const Text('All modules'),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(small ? 10 : 22, 10, small ? 10 : 22, 2),
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
                          if (_generalInMill && _module == null) back,
                          navigation,
                          catalog,
                          _periodPicker(),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    if (_module != null) overviewBack,
                    brand,
                    const SizedBox(width: 10),
                    const SizedBox(height: 18, child: VerticalDivider()),
                    if (_generalInMill && _module == null) back,
                    navigation,
                    catalog,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: company,
                      ),
                    ),
                    _periodPicker(),
                    tools,
                  ],
                ),
        ),
      );
    },
  );
  Widget _periodPicker() => PopupMenuButton<ReportingPeriod>(
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
      constraints: const BoxConstraints(minHeight: 44),
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
            style: const TextStyle(fontSize: 10, color: WorkspaceTheme.ink),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 15),
        ],
      ),
    ),
  );
}
