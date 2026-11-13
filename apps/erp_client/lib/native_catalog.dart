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
          widget.create ? 'NEW DOCUMENT' : 'ALL MODULES & SETTINGS',
          size: 27,
        ),
      ),
      body: FutureBuilder<NativeCatalog>(
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
  @override
  Widget build(BuildContext context) {
    final types = widget.catalog.types
        .where(
          (t) =>
              (!widget.create || t.canCreate) &&
              '${t.name} ${t.module}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    final reports = widget.catalog.reports
        .where(
          (r) => '${r['name']} ${r['module']}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onReport != null && !widget.create) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Records')),
                ButtonSegment(value: true, label: Text('Reports')),
              ],
              selected: {_reports},
              onSelectionChanged: (selection) =>
                  setState(() => _reports = selection.first),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search every module, record type or setting…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 14),
          Text(
            _reports
                ? '${reports.length} available reports'
                : '${types.length} available record types',
            style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: (_reports ? reports.isEmpty : types.isEmpty)
                ? const Center(child: Text('No matching record types.'))
                : ListView.builder(
                    itemCount: _reports ? reports.length : types.length,
                    itemBuilder: (context, i) {
                      if (_reports) {
                        final report = reports[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Material(
                            color: WorkspaceTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              leading: const Icon(
                                Icons.table_chart_outlined,
                                size: 21,
                              ),
                              title: Text(report['name'] as String),
                              subtitle: Text(
                                report['module']?.toString() ?? '',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  widget.onReport!(report['name'] as String),
                            ),
                          ),
                        );
                      }
                      final t = types[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: WorkspaceTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            leading: Icon(
                              t.single
                                  ? Icons.settings_outlined
                                  : Icons.description_outlined,
                              size: 21,
                            ),
                            title: Text(t.name),
                            subtitle: Text(
                              '${t.module}${t.single ? ' · Settings' : ''}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onType(t),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
      final fresh = _load();
      setState(() {
        _future = fresh;
      });
      await fresh;
    },
    child: Scaffold(
      appBar: AppBar(
        title: Display(widget.type.name.toUpperCase(), size: 27),
        actions: [
          if (widget.type.tree)
            IconButton(
              tooltip: 'Browse hierarchy',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NativeTreeScreen(
                      api: widget.api,
                      type: widget.type,
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
          if (widget.type.canCreate)
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
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
                          : 'Create a record or try another search.',
                      label: _start > 0 ? 'Back to first page' : 'Refresh',
                      action: () => _reload(reset: true),
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, i) => const SizedBox(height: 7),
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            final titles = row.entries
                                .where(
                                  (e) => e.key != 'name' && e.key != 'modified',
                                )
                                .map((e) => e.value?.toString() ?? '')
                                .where((v) => v.isNotEmpty);
                            return Material(
                              color: WorkspaceTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                title: Text(
                                  titles.isEmpty
                                      ? row['name'].toString()
                                      : titles.first,
                                ),
                                subtitle: Text(row['name'].toString()),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(row['name'] as String),
                              ),
                            );
                          },
                        ),
                      ),
                      Row(
                        children: [
                          Text('Showing ${_start + 1}–${_start + rows.length}'),
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
  );
}
