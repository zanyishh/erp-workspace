import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_models.dart';
import 'widgets.dart';

typedef RecordLoader =
    Future<List<ErpRecord>> Function(String query, int start);

class ModuleBrowser extends StatefulWidget {
  const ModuleBrowser({
    super.key,
    required this.module,
    required this.company,
    required this.currency,
    required this.loader,
    required this.onRecord,
    required this.onCreate,
    required this.onBrowseAll,
  });
  final ErpModule module;
  final String company, currency;
  final RecordLoader loader;
  final ValueChanged<ErpRecord> onRecord;
  final VoidCallback onCreate, onBrowseAll;
  @override
  State<ModuleBrowser> createState() => _ModuleBrowserState();
}

class _ModuleBrowserState extends State<ModuleBrowser> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _start = 0;
  late Future<List<ErpRecord>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.loader('', 0);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload({bool reset = false}) {
    if (reset) _start = 0;
    setState(() {
      _future = widget.loader(_search.text, _start);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, b) {
      final compact = b.maxWidth < 780;
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          16,
          compact ? 16 : 24,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 15,
              runSpacing: 10,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Display(widget.module.label.toUpperCase(), size: 43),
                    const SizedBox(height: 7),
                    Text(
                      '${widget.module.description} · ${widget.company}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: WorkspaceTheme.muted,
                      ),
                    ),
                  ],
                ),
                Pill(
                  'All records',
                  icon: Icons.apps,
                  onPressed: widget.onBrowseAll,
                  outline: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.module.label.toLowerCase()}…',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          _debounce?.cancel();
                          _reload(reset: true);
                        },
                        icon: const Icon(Icons.close, size: 15),
                      ),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 350),
                        () => _reload(reset: true),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                CircleControl(
                  icon: Icons.refresh,
                  label: 'Refresh records',
                  onPressed: () => _reload(),
                ),
                const SizedBox(width: 4),
                Pill(
                  compact
                      ? 'New'
                      : 'New ${widget.module.doctype.toLowerCase()}',
                  icon: Icons.add,
                  onPressed: widget.onCreate,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<ErpRecord>>(
                future: _future,
                builder: (context, state) {
                  if (state.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: WorkspaceTheme.ink,
                        strokeWidth: 2,
                      ),
                    );
                  }
                  if (state.hasError) {
                    return MessagePanel(
                      title: 'LET’S TRY THAT AGAIN',
                      message: state.error.toString(),
                      action: () => _reload(),
                    );
                  }
                  final rows = state.data ?? [];
                  if (rows.isEmpty && _start > 0) {
                    return MessagePanel(
                      title: 'END OF LIST',
                      message: 'There are no more records in this view.',
                      label: 'Back to first page',
                      action: () => _reload(reset: true),
                    );
                  }
                  if (rows.isEmpty) {
                    return MessagePanel(
                      title: _search.text.trim().isEmpty
                          ? 'A FRESH START'
                          : 'NO MATCHES',
                      message: _search.text.trim().isEmpty
                          ? 'No ${widget.module.doctype.toLowerCase()} records in this view yet. Create your first record here.'
                          : 'Try a different name or document number.',
                      label: _search.text.trim().isEmpty
                          ? 'Create record'
                          : 'Clear search',
                      action: _search.text.trim().isEmpty
                          ? widget.onCreate
                          : () {
                              _search.clear();
                              _reload(reset: true);
                            },
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: Panel(
                          dark: !compact,
                          padding: EdgeInsets.all(compact ? 0 : 8),
                          child: Column(
                            children: [
                              if (!compact)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(20, 9, 20, 14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          'RECORD',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: WorkspaceTheme.light,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'DOCUMENT',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: WorkspaceTheme.light,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'STATUS',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: WorkspaceTheme.light,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          'DETAIL',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: WorkspaceTheme.light,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: rows.length,
                                  separatorBuilder: (_, i) =>
                                      SizedBox(height: compact ? 9 : 5),
                                  itemBuilder: (context, i) =>
                                      _record(rows[i], compact),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Showing ${_start + 1}–${_start + rows.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: WorkspaceTheme.muted,
                            ),
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
            const SizedBox(height: 7),
            const Text(
              'Select a record to view or edit it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: WorkspaceTheme.muted),
            ),
          ],
        ),
      );
      // A phone keyboard can leave less room than the module controls need.
      // Scroll the entire browser then, retaining a useful record-list area.
      return b.maxHeight < 360
          ? SingleChildScrollView(child: SizedBox(height: 600, child: content))
          : content;
    },
  );
  Widget _record(ErpRecord record, bool compact) {
    final detail = record.amount == null
        ? 'Open document'
        : widget.module == ErpModule.manufacturing
        ? '${record.amount!.toString().replaceFirst(RegExp(r'\.0$'), '')} units'
        : money(record.amount!, record.currency ?? widget.currency);
    return Material(
      color: WorkspaceTheme.surface,
      borderRadius: BorderRadius.circular(compact ? 18 : 13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onRecord(record),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_outward, size: 16),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      record.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: WorkspaceTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        StatusChip(record.status),
                        const Spacer(),
                        Text(detail, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(
                        record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: WorkspaceTheme.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(record.status),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        detail,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
