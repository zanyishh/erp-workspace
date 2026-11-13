import 'ui/access_gate.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'report_screen.dart';
import 'native_tree.dart';
import 'widgets.dart';

class NativeCatalogScreen extends StatefulWidget {
  const NativeCatalogScreen({
    super.key,
    required this.api,
    this.company,
    this.create = false,
  });
  final ErpApi api;
  final String? company;
  final bool create;
  @override
  State<NativeCatalogScreen> createState() => _NativeCatalogScreenState();
}

class _NativeCatalogScreenState extends State<NativeCatalogScreen> {
  late Future<NativeCatalog> _future = widget.api.nativeCatalog(
    company: widget.company,
  );
  void _open(NativeType type) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => widget.create || type.single
          ? DocumentEditor(
              api: widget.api,
              doctype: type.name,
              company: widget.company,
            )
          : NativeRecordScreen(
              api: widget.api,
              type: type,
              company: widget.company,
            ),
    ),
  );
  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      final fresh = widget.api.nativeCatalog(company: widget.company);
      setState(() {
        _future = fresh;
      });
      await fresh;
    },
    child: Scaffold(
      appBar: AppBar(
        title: Display(
          widget.create ? 'New document' : 'All modules & settings',
          size: 27,
        ),
      ),
      body: WorkspaceBackdrop(
        child: FutureBuilder<NativeCatalog>(
          future: _future,
          builder: (context, state) {
            if (state.hasData) {
              return NativeCatalogView(
                catalog: state.data!,
                onType: _open,
                onReport: (name) => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NativeReportScreen(
                      api: widget.api,
                      name: name,
                      company: widget.company,
                    ),
                  ),
                ),
                create: widget.create,
              );
            }
            if (state.hasError) {
              return MessagePanel(
                title: 'COULD NOT LOAD MODULES',
                message: state.error.toString(),
                action: () => setState(() {
                  _future = widget.api.nativeCatalog(company: widget.company);
                }),
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    ),
  );
}

class NativeCatalogView extends StatefulWidget {
  const NativeCatalogView({
    super.key,
    required this.catalog,
    required this.onType,
    this.onReport,
    this.create = false,
  });
  final NativeCatalog catalog;
  final ValueChanged<NativeType> onType;
  final ValueChanged<String>? onReport;
  final bool create;
  @override
  State<NativeCatalogView> createState() => _NativeCatalogViewState();
}

class _NativeCatalogViewState extends State<NativeCatalogView> {
  String _query = '';
  bool _reports = false;
  String _module = '';

  @override
  Widget build(BuildContext context) {
    final allowed = widget.catalog.types.where(
      (type) => !widget.create || type.canCreate && !type.single,
    );
    final showReports = !widget.create && widget.onReport != null;
    final modules = {
      for (final type in allowed) type.module,
      if (showReports)
        for (final report in widget.catalog.reports)
          report['module']?.toString() ?? 'Other',
    }.toList()..sort();
    final module = modules.contains(_module) ? _module : '';
    final query = _query.trim().toLowerCase();
    bool matches(String name, String group) =>
        (module.isEmpty || module == group) &&
        '$name $group'.toLowerCase().contains(query);
    final types = allowed.where((t) => matches(t.name, t.module)).toList();
    final reports = widget.catalog.reports
        .where(
          (r) =>
              matches(r['name'] as String, r['module']?.toString() ?? 'Other'),
        )
        .toList();
    final count = _reports ? reports.length : types.length;

    return LayoutBuilder(
      builder: (context, box) {
        final desktop = box.maxWidth >= 900;
        Widget moduleFilter() => PopupMenuButton<String>(
          tooltip: 'Filter by module',
          initialValue: module,
          onSelected: (value) => setState(() => _module = value),
          itemBuilder: (_) => [
            for (final name in ['', ...modules])
              PopupMenuItem(
                value: name,
                child: Text(name.isEmpty ? 'All modules' : name),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(module.isEmpty ? 'All modules' : module)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );

        final list = CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (desktop)
                          Display(
                            module.isEmpty ? 'All modules' : module,
                            size: 34,
                          )
                        else
                          moduleFilter(),
                        if (showReports)
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: WorkspaceTheme.charcoal,
                              selectedForegroundColor: WorkspaceTheme.light,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Records'),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Reports'),
                              ),
                            ],
                            selected: {_reports},
                            onSelectionChanged: (value) =>
                                setState(() => _reports = value.first),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        hintText: _reports
                            ? 'Search reports or modules…'
                            : 'Search record types or modules…',
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _reports
                          ? '$count available reports'
                          : '$count available record types',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (count == 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    _reports
                        ? 'No matching reports.'
                        : 'No matching record types.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: count,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final type = _reports ? null : types[i];
                  final report = _reports ? reports[i] : null;
                  final name = type?.name ?? report!['name'] as String;
                  final group =
                      type?.module ?? report!['module']?.toString() ?? 'Other';
                  return Material(
                    color: WorkspaceTheme.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      minVerticalPadding: 6,
                      minTileHeight: module.isEmpty ? 60 : 50,
                      leading: Icon(
                        _reports
                            ? Icons.table_chart_outlined
                            : type!.single
                            ? Icons.settings_outlined
                            : Icons.description_outlined,
                        size: 20,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: module.isNotEmpty && type?.single != true
                          ? null
                          : Text(
                              type?.single == true
                                  ? (module.isEmpty
                                        ? '$group · Settings'
                                        : 'Settings')
                                  : group,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => type == null
                          ? widget.onReport!(name)
                          : widget.onType(type),
                    ),
                  );
                },
              ),
          ],
        );
        return Padding(
          padding: EdgeInsets.all(desktop ? 24 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop) ...[
                SizedBox(
                  width: 222,
                  child: Panel(
                    dark: true,
                    frosted: true,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Display('Modules', size: 26, light: true),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final name in ['', ...modules])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Material(
                                    color: module == name
                                        ? WorkspaceTheme.palePeach
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListTile(
                                      dense: true,
                                      minTileHeight: 44,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                      minVerticalPadding: 4,
                                      selected: module == name,
                                      textColor: WorkspaceTheme.light,
                                      selectedColor: WorkspaceTheme.ink,
                                      title: Text(
                                        name.isEmpty ? 'All modules' : name,
                                      ),
                                      onTap: () =>
                                          setState(() => _module = name),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 22),
              ],
              Expanded(child: list),
            ],
          ),
        );
      },
    );
  }
}

class NativeRecordScreen extends StatefulWidget {
  const NativeRecordScreen({
    super.key,
    required this.api,
    required this.type,
    this.company,
  });
  final ErpApi api;
  final NativeType type;
  final String? company;
  @override
  State<NativeRecordScreen> createState() => _NativeRecordScreenState();
}

class _NativeRecordScreenState extends State<NativeRecordScreen> {
  late NativeType _type = widget.type;
  late Future<List<Map<String, dynamic>>> _future = _load();
  Timer? _debounce;
  String _query = '';
  int _start = 0;
  Future<List<Map<String, dynamic>>> _load() => widget.api.nativeRecords(
    widget.type.name,
    company: widget.company,
    query: _query,
    start: _start,
  );
  void _reload({bool reset = false}) {
    if (reset) _start = 0;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open([String? name]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: widget.api,
          doctype: widget.type.name,
          name: name,
          company: widget.company,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      final revision = widget.api.accessRevision;
      final catalog = await widget.api.nativeCatalog(company: widget.company);
      if (!mounted || widget.api.accessRevision != revision) return;
      final type = catalog.types
          .where((t) => t.name == widget.type.name)
          .firstOrNull;
      if (type == null) {
        throw const ErpException('This record type is no longer available.');
      }
      final fresh = _load();
      setState(() {
        _type = type;
        _future = fresh;
      });
      await fresh;
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.type.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_type.tree)
            IconButton(
              tooltip: 'Browse hierarchy',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NativeTreeScreen(
                      api: widget.api,
                      type: _type,
                      company: widget.company,
                    ),
                  ),
                );
                if (mounted) _reload();
              },
              icon: const Icon(Icons.account_tree_outlined),
            ),
          IconButton(
            tooltip: 'Refresh records',
            onPressed: () => _reload(),
            icon: const Icon(Icons.refresh),
          ),
          if (_type.canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => _open(),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: WorkspaceBackdrop(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    [
                      _type.module,
                      if (widget.company != null) widget.company!,
                    ].join('  /  '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.type.name.toLowerCase()}…',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    _query = value;
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _reload(reset: true),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, state) {
                      if (state.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.hasError) {
                        return MessagePanel(
                          title: 'COULD NOT LOAD',
                          message: state.error.toString(),
                          action: () => _reload(),
                        );
                      }
                      final rows = state.data ?? [];
                      if (rows.isEmpty) {
                        return MessagePanel(
                          title: _start > 0 ? 'END OF LIST' : 'NO RECORDS',
                          message: _start > 0
                              ? 'There are no more records in this view.'
                              : _query.isNotEmpty
                              ? 'Try another name or document number.'
                              : 'No ${widget.type.name} records are available in this view.',
                          label: _start > 0 ? 'Back to first page' : 'Refresh',
                          action: () => _reload(reset: true),
                        );
                      }
                      return Column(
                        children: [
                          Expanded(
                            child: Panel(
                              frosted: true,
                              padding: EdgeInsets.zero,
                              child: ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, i) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  final titles = row.entries
                                      .where(
                                        (e) =>
                                            e.key != 'name' &&
                                            e.key != 'modified',
                                      )
                                      .map((e) => e.value?.toString() ?? '')
                                      .where((v) => v.isNotEmpty);
                                  final name = row['name'] as String;
                                  final title = titles.firstOrNull ?? name;
                                  final date = row['modified']
                                      ?.toString()
                                      .split(' ')
                                      .first;
                                  final wide =
                                      MediaQuery.sizeOf(context).width >= 700;
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                      minVerticalPadding: 6,
                                      title: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: title == name
                                          ? null
                                          : Text(name),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (wide && date != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              child: Text(
                                                date,
                                                semanticsLabel:
                                                    'Modified $date',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ),
                                          const Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _open(name),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'Showing ${_start + 1}–${_start + rows.length}',
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: _start == 0
                                    ? null
                                    : () {
                                        _start = (_start - 50).clamp(0, _start);
                                        _reload();
                                      },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: rows.length < 50
                                    ? null
                                    : () {
                                        _start += 50;
                                        _reload();
                                      },
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
