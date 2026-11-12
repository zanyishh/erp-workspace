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
import 'session_recovery.dart';
import 'widgets.dart';
import 'workspace_picker.dart';

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
  const WorkspaceShell({super.key});
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  ErpApi? _api;
  Future<ErpSnapshot>? _snapshot;
  ReportingPeriod _period = ReportingPeriod.month;
  ErpModule? _module;
  ErpSnapshot? _lastData;
  int _revision = 0;
  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _signIn(String server, String username, String password) async {
    final api = ErpApi(Uri.parse(server));
    try {
      await api.login(username, password);
      if (!mounted) {
        api.close();
        return;
      }
      api.onSessionExpired = () => _recoverSession(api);
      setState(() {
        _api = api;
        _module = null;
        _snapshot = _guard(api, api.snapshot(_period));
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
    if (restored == true) return true;
    if (mounted && identical(_api, api)) {
      api.onSessionExpired = null;
      api.close();
      setState(() {
        _api = null;
        _snapshot = null;
        _lastData = null;
      });
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WorkspaceShell()),
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
          _lastData = null;
        });
      }
      rethrow;
    }
  }

  void _refresh() {
    final api = _api;
    if (api == null) return;
    setState(() {
      _revision++;
      _snapshot = _guard(
        api,
        api.snapshot(_period, selectedCompany: _lastData?.company),
      );
    });
  }

  Future<void> _signOut() async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _api = null;
      _snapshot = null;
      _lastData = null;
      _module = null;
    });
    try {
      await api.signOut();
    } catch (_) {
      /* Local sign-out remains effective if the service is unavailable. */
    } finally {
      api.close();
    }
  }

  void _licenses() => showLicensePage(
    context: context,
    applicationName: 'ERP Workspace',
    applicationVersion: '0.1.0',
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

  void _select(ErpModule? module) => setState(() => _module = module);
  void _moduleMenu() =>
      showWorkspacePicker(context, _select, onAll: () => _catalog());

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
          company: _lastData?.company,
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
          company: _lastData?.company,
          create: create,
        ),
      ),
    );
    if (mounted && identical(_api, api)) _refresh();
  }

  void _newDocument() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkspaceTheme.canvas,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 570),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Display('MAKE SOMETHING HAPPEN.', size: 32),
                const SizedBox(height: 10),
                const Text(
                  'Choose a document to create in your workspace.',
                  style: TextStyle(fontSize: 12, color: WorkspaceTheme.muted),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.apps),
                        title: const Text('All record types'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(c);
                          _catalog(create: true);
                        },
                      ),
                      for (final m in ErpModule.values)
                        ListTile(
                          leading: Icon(moduleIcon(m)),
                          title: Text(m.doctype),
                          trailing: const Icon(Icons.arrow_outward, size: 17),
                          onTap: () {
                            Navigator.pop(c);
                            _edit(m.doctype);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _settings() {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: WorkspaceTheme.canvas,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Display('YOUR WORKSPACE', size: 31)),
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
                Text(
                  _api?.baseUri.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WorkspaceTheme.muted,
                  ),
                ),
                const SizedBox(height: 19),
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

  void _activity() {
    final data = _lastData;
    if (data == null) return;
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: WorkspaceTheme.canvas,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Display('RECENT ACTIVITY', size: 29)),
                    IconButton(
                      tooltip: 'Close activity',
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data.activity.isEmpty)
                  const Text(
                    'No invoices in this period yet. Your latest changes will appear here.',
                    style: TextStyle(color: WorkspaceTheme.muted, height: 1.6),
                  ),
                for (final r in data.activity)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(r.title),
                    subtitle: Text(r.name),
                    trailing: Text(r.status),
                    onTap: () {
                      Navigator.pop(c);
                      _edit(r.module.doctype, name: r.name);
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
      return SignInScreen(onSignIn: _signIn, onLicenses: _licenses);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _moduleMenu,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _refresh,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: FutureBuilder<ErpSnapshot>(
              future: _snapshot,
              builder: (context, state) {
                final data = state.connectionState == ConnectionState.done
                    ? state.data
                    : null;
                if (data != null) _lastData = data;
                return Column(
                  children: [
                    _header(data, api),
                    Expanded(
                      child: state.connectionState != ConnectionState.done
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: WorkspaceTheme.ink,
                              ),
                            )
                          : state.hasError
                          ? MessagePanel(
                              title: 'LET’S RECONNECT',
                              message: state.error.toString(),
                              action: _refresh,
                            )
                          : _module == null
                          ? OverviewScreen(
                              data: data!,
                              onModule: _select,
                              onNew: _newDocument,
                            )
                          : ModuleBrowser(
                              key: ValueKey(
                                '${_module!.name}-${_period.name}-$_revision',
                              ),
                              module: _module!,
                              company: data!.company,
                              currency: data.currency,
                              loader: (query, start) => _guard(
                                api,
                                api.records(
                                  _module!,
                                  company: data.company,
                                  period: _period,
                                  query: query,
                                  start: start,
                                ),
                              ),
                              onRecord: (r) =>
                                  _edit(r.module.doctype, name: r.name),
                              onCreate: () => _edit(_module!.doctype),
                              onBrowseAll: () => _catalog(),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ErpSnapshot? data, ErpApi api) => LayoutBuilder(
    builder: (context, b) {
      final wide = b.maxWidth >= 1180;
      final utilities = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleControl(
            icon: Icons.history,
            label: 'Recent invoice activity',
            onPressed: _activity,
          ),
          CircleControl(
            icon: Icons.search,
            label: 'Search workspaces',
            onPressed: _moduleMenu,
          ),
          CircleControl(
            icon: Icons.refresh,
            label: 'Refresh workspace',
            onPressed: _refresh,
          ),
          const SizedBox(width: 5),
          Tooltip(
            message: 'Account and settings',
            child: IconButton(
              onPressed: _settings,
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: WorkspaceTheme.palePeach,
                child: Text(
                  api.userName.isEmpty ? 'A' : api.userName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: WorkspaceTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      final navigation = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Pill(
              _module?.label ?? 'Business overview',
              icon: _module == null
                  ? Icons.space_dashboard_outlined
                  : moduleIcon(_module!),
              onPressed: _moduleMenu,
            ),
          ),
          const SizedBox(width: 5),
          CircleControl(
            icon: Icons.home_outlined,
            label: 'Business overview',
            onPressed: () => _select(null),
          ),
          if (wide) ...[
            CircleControl(
              icon: Icons.inventory_2_outlined,
              label: 'Browse inventory',
              onPressed: () => _select(ErpModule.stock),
            ),
            CircleControl(
              icon: Icons.grid_view_outlined,
              label: 'Browse projects',
              onPressed: () => _select(ErpModule.projects),
            ),
          ],
        ],
      );
      Widget stats() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _topMetric(
            'Catalog\nitems',
            data == null ? '—' : tally(data.count(ErpModule.stock)),
          ),
          _topMetric(
            'Sales\norders',
            data == null ? '—' : tally(data.count(ErpModule.selling)),
          ),
          _topMetric(
            'Warehouse\nlocations',
            data == null ? '—' : tally(data.warehouses),
          ),
          _topMetric(
            'Customer\naccounts',
            data == null ? '—' : tally(data.customers),
            last: true,
          ),
        ],
      );
      return Container(
        padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 14, wide ? 24 : 16, 9),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: WorkspaceTheme.border, width: .6),
          ),
        ),
        child: Column(
          children: [
            if (wide)
              Row(
                children: [
                  const Display('WORKSPACE.', size: 26),
                  const SizedBox(width: 23),
                  navigation,
                  const SizedBox(width: 18),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: stats(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _periodPicker(),
                  const SizedBox(width: 8),
                  utilities,
                ],
              )
            else ...[
              Row(
                children: [
                  const Expanded(child: Display('WORKSPACE.', size: 27)),
                  utilities,
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: navigation),
                  const SizedBox(width: 8),
                  _periodPicker(),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: stats(),
              ),
            ],
          ],
        ),
      );
    },
  );
  Widget _topMetric(String label, String value, {bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(right: BorderSide(color: WorkspaceTheme.border)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                height: 1.4,
                color: WorkspaceTheme.muted,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
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
