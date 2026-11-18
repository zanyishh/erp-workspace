import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/native_models.dart';
import '../../../core/ui/retained_load.dart';
import '../../../core/ui/widgets.dart';
import '../models/catalog_models.dart';
import 'native_records_view_model.dart';

class NativeRecordsView extends StatefulWidget {
  const NativeRecordsView({
    super.key,
    required this.model,
    required this.open,
    required this.chooseGroup,
    required this.protect,
    this.importCsv,
    this.openTasks,
    this.browseTree,
  });
  final NativeRecordsViewModel model;
  final Future<void> Function(String?) open;
  final Future<String?> Function(GroupChangeIntent) chooseGroup;
  final Future<void> Function()? importCsv, openTasks, browseTree;
  final Widget Function(Widget, Future<void> Function()) protect;
  NativeType get type => model.type;
  String? get company => model.company;
  @override
  State<NativeRecordsView> createState() => _NativeRecordsViewState();
}

class _NativeRecordsViewState extends State<NativeRecordsView> {
  final _search = TextEditingController();
  Timer? _debounce;
  final _rowFocus = <String, FocusNode>{};
  NativeType get _type => widget.model.type;
  int get _start => widget.model.start;
  String get _query => widget.model.query;
  String? get _openedRecord => widget.model.openedRecord;
  bool get _selecting => widget.model.selecting;
  bool get _savingGroup => widget.model.savingGroup;
  Map<String, String> get _selected => widget.model.selected;
  Future<NativeRecordPage> get _future => widget.model.result;
  void _resetControls() {
    for (final node in _rowFocus.values) {
      node.unfocus();
    }
    _debounce?.cancel();
    _search.clear();
  }

  @override
  void didUpdateWidget(covariant NativeRecordsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _resetControls();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _reload({bool reset = false}) {
    _debounce?.cancel();
    setState(() {
      widget.model.reload(query: _search.text, reset: reset);
    });
  }

  void _page(bool forward) {
    _debounce?.cancel();
    setState(() {
      if (forward) {
        widget.model.nextPage(query: _search.text);
      } else {
        widget.model.previousPage(query: _search.text);
      }
    });
  }

  void _clearSearch() {
    _search.clear();
    _reload(reset: true);
  }

  void _toggle(String name, String modified) {
    if (!widget.model.toggle(name, modified)) {
      if (widget.model.selectionLimitReached) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select up to 50 records.')),
        );
      }
      return;
    }
    setState(() {});
  }

  Future<void> _changeGroup() async {
    final model = widget.model, scope = widget.model.scope;
    final intent = model.prepareGroupChange();
    if (intent == null) {
      return;
    }
    final chosen = await widget.chooseGroup(intent);
    if (!mounted ||
        chosen == null ||
        model != widget.model ||
        scope != model.scope) {
      return;
    }
    final changing = model.applyGroup(intent, chosen);
    setState(() {});
    try {
      final count = await changing;
      if (!mounted ||
          model != widget.model ||
          scope != model.scope ||
          count == null) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Group updated on $count ${count == 1 ? 'record' : 'records'}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted && model == widget.model && scope == model.scope) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && model == widget.model) {
        setState(() {});
      }
    }
  }

  Future<void> _open([String? name]) async {
    final model = widget.model;
    if (!model.opened(name)) {
      return;
    }
    _rowFocus[name]?.requestFocus();
    await widget.open(name);
    if (mounted && model == widget.model) {
      _reload();
    }
  }

  Future<void> _navigate(
    Future<void> Function() route, {
    bool reset = false,
  }) async {
    final model = widget.model;
    if (!model.active) {
      return;
    }
    await route();
    if (mounted && model == widget.model) {
      _reload(reset: reset);
    }
  }

  Future<void> _revalidate() async {
    _resetControls();
    final checking = widget.model.revalidate();
    setState(() {});
    await checking;
  }

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: _appBar(),
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
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.type.name.toLowerCase()}…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _reload(reset: true),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _results(),
              ],
            ),
          ),
        ),
      ),
    ),
    _revalidate,
  );
  Widget _record(Map<String, dynamic> row) {
    final titles = row.entries
        .where((e) => e.key != 'name' && e.key != 'modified')
        .map((e) => e.value?.toString() ?? '')
        .where((v) => v.isNotEmpty);
    final name = row['name'] as String;
    final title = titles.firstOrNull ?? name;
    final date = row['modified']?.toString().split(' ').first;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Material(
      key: ValueKey(name),
      color: Colors.transparent,
      child: ListTile(
        focusNode: _rowFocus.putIfAbsent(
          name,
          () => FocusNode(debugLabel: name),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 6,
        leading: _selecting
            ? Checkbox(
                value: _selected.containsKey(name),
                onChanged: row['modified'] is String && !_savingGroup
                    ? (_) => _toggle(name, row['modified'] as String)
                    : null,
              )
            : null,
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: title == name ? null : Text(name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide && date != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  date,
                  semanticsLabel: 'Modified $date',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: _selecting
            ? row['modified'] is String && !_savingGroup
                  ? () => _toggle(name, row['modified'] as String)
                  : null
            : () => _open(name),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final actions = <({String label, IconData icon, VoidCallback? run})>[
      if (_type.canGroup && widget.company != null)
        (
          label: _selecting ? 'Cancel selection' : 'Select records',
          icon: _selecting ? Icons.close : Icons.checklist,
          run: _savingGroup
              ? null
              : () => setState(widget.model.toggleSelecting),
        ),
      if (_selecting)
        (
          label: 'Change group',
          icon: Icons.drive_file_move_outlined,
          run: _selected.isEmpty || _savingGroup ? null : _changeGroup,
        )
      else ...[
        if (_type.canImport && widget.company != null)
          (
            label: 'Import CSV',
            icon: Icons.upload_file_outlined,
            run: widget.importCsv == null
                ? null
                : () => _navigate(widget.importCsv!, reset: true),
          ),
        if (_type.name == 'Task' && widget.company != null)
          (
            label: 'Task board and calendar',
            icon: Icons.view_kanban_outlined,
            run: widget.openTasks == null
                ? null
                : () => _navigate(widget.openTasks!),
          ),
        if (_type.tree)
          (
            label: 'Browse hierarchy',
            icon: Icons.account_tree_outlined,
            run: widget.browseTree == null
                ? null
                : () => _navigate(widget.browseTree!),
          ),
      ],
    ];
    return AppBar(
      title: Text(
        _selecting ? '${_selected.length} selected' : widget.type.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (!compact || _selecting)
          for (final action in actions)
            IconButton(
              tooltip: action.label,
              icon: Icon(action.icon),
              onPressed: action.run,
            ),
        if (!_selecting) ...[
          IconButton(
            tooltip: 'Refresh records',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          if (compact && actions.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'Record actions',
              onSelected: (index) => actions[index].run?.call(),
              itemBuilder: (_) => [
                for (final (index, action) in actions.indexed)
                  PopupMenuItem(
                    value: index,
                    enabled: action.run != null,
                    child: Row(
                      children: [
                        Icon(action.icon, size: 20),
                        const SizedBox(width: 12),
                        Flexible(child: Text(action.label)),
                      ],
                    ),
                  ),
              ],
            ),
          if (_type.canCreate)
            Padding(
              padding: EdgeInsetsDirectional.only(end: compact ? 4 : 12),
              child: compact
                  ? IconButton.filled(
                      tooltip: 'New ${_type.name}',
                      icon: const Icon(Icons.add),
                      onPressed: () => _open(),
                    )
                  : FilledButton.icon(
                      onPressed: () => _open(),
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
            ),
        ],
      ],
    );
  }

  Widget _pager(NativeRecordPage page) => Row(
    children: [
      Text('Showing ${_start + 1}–${_start + page.rows.length}'),
      const Spacer(),
      IconButton(
        tooltip: 'Previous page',
        onPressed: _start == 0
            ? null
            : () {
                _page(false);
              },
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: !page.hasMore
            ? null
            : () {
                _page(true);
              },
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Widget _recordList(List<Map<String, dynamic>> rows) => Expanded(
    child: Panel(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        key: PageStorageKey((widget.model.scope, _query, _start)),
        itemCount: rows.length,
        findItemIndexCallback: (key) {
          final index = rows.indexWhere(
            (row) => key is ValueKey && key.value == row['name'],
          );
          return index < 0 ? null : index;
        },
        separatorBuilder: (_, i) => const Divider(height: 1),
        itemBuilder: (context, i) => _record(rows[i]),
      ),
    ),
  );
  Widget _results() => Expanded(
    child: RetainedFutureBuilder<NativeRecordPage>(
      future: _future,
      scope: (widget.model.scope, _query, _start),
      builder: (context, state) {
        if (state.loading && !state.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError && !state.hasData) {
          return MessagePanel(
            title: 'COULD NOT LOAD',
            message: state.error.toString(),
            action: () => _reload(),
          );
        }
        final rows = state.data?.rows ?? [];
        if (rows.isEmpty) {
          final filtered = _search.text.trim().isNotEmpty;
          return MessagePanel(
            title: _start > 0
                ? 'END OF LIST'
                : filtered
                ? 'NO MATCHES'
                : 'NO RECORDS',
            message: _openedRecord != null
                ? 'The opened record is no longer in this view.'
                : _start > 0
                ? 'There are no more records in this view.'
                : filtered
                ? 'Try another name or document number.'
                : 'No ${widget.type.name} records are available in this view.',
            label: _start > 0
                ? 'Back to first page'
                : filtered
                ? 'Clear search'
                : _type.canCreate
                ? 'Create ${_type.name.toLowerCase()}'
                : 'Refresh',
            action: _start > 0
                ? () => _reload(reset: true)
                : filtered
                ? _clearSearch
                : _type.canCreate
                ? () => _open()
                : () => _reload(),
          );
        }
        return Column(
          children: [
            RetainedLoadNotice(
              loading: state.loading,
              error: state.error,
              onRetry: _reload,
            ),
            if (_openedRecord != null &&
                !rows.any((r) => r['name'] == _openedRecord))
              const Text(
                'The opened record is no longer in this view. The remaining records are shown.',
              ),
            _recordList(rows),
            _pager(state.data!),
          ],
        );
      },
    ),
  );
}
