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
                    Text(
                      widget.module.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Display(widget.module.doctype, size: 38),
                    const SizedBox(height: 7),
                    Text(
                      widget.company,
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
                  light: true,
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
                      hintText: compact
                          ? 'Search records…'
                          : 'Search name or document number…',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
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
                      setState(() {});
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
                          frosted: true,
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              if (!compact)
                                ColoredBox(
                                  color: WorkspaceTheme.charcoal,
                                  child: DefaultTextStyle(
                                    style: const TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 12,
                                      color: WorkspaceTheme.light,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            flex: 4,
                                            child: Text('Record'),
                                          ),
                                          const Expanded(
                                            flex: 3,
                                            child: Text('Document number'),
                                          ),
                                          const Expanded(
                                            flex: 2,
                                            child: Text('Status'),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              widget.module.amountField == null
                                                  ? 'Last modified'
                                                  : widget.module ==
                                                        ErpModule.manufacturing
                                                  ? 'Quantity'
                                                  : 'Amount',
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                          const SizedBox(width: 28),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: rows.length,
                                  separatorBuilder: (_, i) =>
                                      const Divider(height: 1),
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
        ? record.data['modified']?.toString().split(' ').first ?? '—'
        : widget.module == ErpModule.manufacturing
        ? '${record.amount!.toString().replaceFirst(RegExp(r'\.0$'), '')} units'
        : money(record.amount!, record.currency ?? widget.currency);
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onRecord(record),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        fontSize: 12,
                        color: WorkspaceTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        if (record.status.isNotEmpty)
                          Flexible(child: StatusChip(record.status)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
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
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WorkspaceTheme.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: record.status.isEmpty
                            ? const Text('—')
                            : StatusChip(record.status),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        detail,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.chevron_right, size: 16),
                  ],
                ),
        ),
      ),
    );
  }
}
