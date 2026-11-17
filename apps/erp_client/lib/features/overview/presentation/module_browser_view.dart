import '../../../core/ui/retained_load.dart';
import '../../../core/ui/record_icon.dart';
import '../../../core/ui/workspace_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../../../core/models/erp_models.dart';
import '../../../core/ui/widgets.dart';

import 'module_browser_view_model.dart';

class ModuleBrowserView extends StatefulWidget {
  const ModuleBrowserView({
    super.key,
    required this.model,
    required this.onRecord,
    required this.onCreate,
    required this.onBrowseAll,
    this.onShowAll,
    this.onReconcile,
    this.onBankMatch,
    this.onCheckout,
    this.onInvoices,
    this.onImportedHistory,
    this.refreshRevision = 0,
    this.showCompany = true,
  });
  final int refreshRevision;
  final bool showCompany;
  Object? get scope => model.scope;
  final VoidCallback? onInvoices;
  final VoidCallback? onImportedHistory;
  final ModuleBrowserViewModel model;
  ErpModule get module => model.module;
  String get company => model.company;
  String get currency => model.currency;
  final ValueChanged<ErpRecord> onRecord;
  final VoidCallback? onCreate;
  final VoidCallback onBrowseAll;
  final VoidCallback? onShowAll;
  final VoidCallback? onReconcile, onBankMatch, onCheckout;
  @override
  State<ModuleBrowserView> createState() => _ModuleBrowserViewState();
}

class _ModuleBrowserViewState extends State<ModuleBrowserView> {
  final _search = TextEditingController();
  Timer? _debounce;
  int get _start => widget.model.start;
  String get _query => widget.model.query;
  String? get _openedRecord => widget.model.openedRecord;
  final _rowFocus = <String, FocusNode>{};
  Future<List<ErpRecord>> get _future => widget.model.result;
  @override
  void didUpdateWidget(covariant ModuleBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _debounce?.cancel();
      _search.clear();
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _reload();
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, b) {
      final compact = b.maxWidth < 780;
      final controls = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 20),
          _controls(compact),
          if (widget.onShowAll != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.filter_alt_outlined, size: 16),
                label: const Text('Unpaid invoices'),
                deleteButtonTooltipMessage: 'Show all invoices',
                onDeleted: widget.onShowAll,
              ),
            ),
          const SizedBox(height: 14),
        ],
      );
      if (b.maxWidth < 600 || b.maxHeight < 360) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _results(compact, scrollingControls: controls),
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          16,
          compact ? 16 : 24,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls,
            Expanded(child: _results(compact)),
          ],
        ),
      );
    },
  );
  Widget _header() => Wrap(
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!workspaceUsesPhoneNavigation(context)) ...[
                RecordHeaderMark(
                  widget.module.doctype,
                  tone: moduleMark(widget.module.label).$2,
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Semantics(
                  headingLevel: 1,
                  child: Display(
                    widget.module.doctype,
                    size: workspaceUsesPhoneNavigation(context) ? 31 : 34,
                  ),
                ),
              ),
            ],
          ),
          if (widget.showCompany) ...[
            const SizedBox(height: 7),
            Text(widget.company, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      if (widget.onImportedHistory != null)
        OutlinedButton.icon(
          onPressed: widget.onImportedHistory,
          icon: const Icon(Icons.history_outlined),
          label: const Text('Original records'),
        ),
      if (widget.onInvoices != null)
        Pill(
          'Invoices',
          icon: Icons.receipt_long_outlined,
          onPressed: widget.onInvoices,
          outline: true,
          light: true,
        ),
      if (widget.onCheckout != null)
        IconButton(
          tooltip: 'Point of sale',
          icon: const Icon(Icons.point_of_sale),
          onPressed: widget.onCheckout,
        ),
      if (widget.onReconcile != null || widget.onBankMatch != null)
        PopupMenuButton<VoidCallback>(
          tooltip: 'Reconciliation',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            if (widget.onReconcile != null)
              PopupMenuItem(
                value: widget.onReconcile,
                child: const Text('Reconcile payments'),
              ),
            if (widget.onBankMatch != null)
              PopupMenuItem(
                value: widget.onBankMatch,
                child: const Text('Match bank statements'),
              ),
          ],
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.compare_arrows),
                SizedBox(width: 6),
                Text('Reconciliation'),
                Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      Pill(
        'All records',
        icon: Icons.apps,
        onPressed: widget.onBrowseAll,
        outline: true,
        light: true,
      ),
    ],
  );

  Widget _controls(bool compact) => Row(
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
      if (widget.onCreate != null) ...[
        const SizedBox(width: 4),
        Pill(
          compact ? 'New' : 'New ${widget.module.doctype.toLowerCase()}',
          icon: Icons.add,
          onPressed: widget.onCreate,
        ),
      ],
    ],
  );

  Widget _tableHeader() => ColoredBox(
    color: WorkspaceTheme.charcoal,
    child: DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        color: WorkspaceTheme.light,
        fontWeight: FontWeight.w600,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Expanded(flex: 4, child: ColumnCaption('Record', dark: true)),
            const Expanded(
              flex: 3,
              child: ColumnCaption('Document number', dark: true),
            ),
            const Expanded(flex: 2, child: ColumnCaption('Status', dark: true)),
            SizedBox(
              width: 120,
              child: ColumnCaption(
                widget.module.amountField == null
                    ? 'Last modified'
                    : widget.module == ErpModule.manufacturing
                    ? 'Quantity'
                    : 'Amount',
                dark: true,
                alignEnd: true,
              ),
            ),
            const SizedBox(width: 28),
          ],
        ),
      ),
    ),
  );

  Widget _recordList(List<ErpRecord> rows, bool compact) => Expanded(
    child: Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (!compact) _tableHeader(),
          Expanded(
            child: ListView.separated(
              key: PageStorageKey((widget.scope, _query, _start)),
              itemCount: rows.length,
              findItemIndexCallback: (key) {
                final index = rows.indexWhere(
                  (row) => key is ValueKey && key.value == row.name,
                );
                return index < 0 ? null : index;
              },
              separatorBuilder: (_, i) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _record(rows[i], compact, key: ValueKey(rows[i].name)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pager(List<ErpRecord> rows) => Row(
    children: [
      Text(
        'Showing ${_start + 1}–${_start + rows.length}',
        style: const TextStyle(fontSize: 11, color: WorkspaceTheme.muted),
      ),
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
        onPressed: rows.length < 50
            ? null
            : () {
                _page(true);
              },
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget? _resultMessage(RetainedLoad<List<ErpRecord>> state) {
    if (state.loading && !state.hasData) {
      return const Center(
        child: CircularProgressIndicator(
          color: WorkspaceTheme.ink,
          strokeWidth: 2,
        ),
      );
    }
    if (state.hasError && !state.hasData) {
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
        message: _openedRecord != null
            ? 'The opened record is no longer in this view. There are no records left on this page.'
            : 'There are no more records in this view.',
        label: 'Back to first page',
        action: () => _reload(reset: true),
      );
    }
    if (rows.isEmpty &&
        widget.onShowAll != null &&
        _search.text.trim().isEmpty) {
      return MessagePanel(
        title: 'No unpaid invoices',
        message: 'No posted invoices in this period have a balance due.',
        action: widget.onShowAll,
        label: 'Show all invoices',
      );
    }
    if (rows.isEmpty) {
      return MessagePanel(
        title: _search.text.trim().isEmpty ? 'NO RECORDS' : 'NO MATCHES',
        message: _openedRecord != null
            ? 'The opened record is no longer in this view.'
            : _search.text.trim().isEmpty
            ? 'No ${widget.module.doctype.toLowerCase()} records in this view.'
            : 'Try a different name or document number.',
        label: _search.text.trim().isEmpty
            ? widget.onCreate == null
                  ? 'Refresh'
                  : 'Create record'
            : 'Clear search',
        action: _search.text.trim().isEmpty
            ? widget.onCreate ?? () => _reload()
            : () {
                _search.clear();
                _reload(reset: true);
              },
      );
    }
    return null;
  }

  Widget _results(bool compact, {Widget? scrollingControls}) =>
      RetainedFutureBuilder<List<ErpRecord>>(
        future: _future,
        scope: (widget.scope, widget.company, widget.module, _query, _start),
        builder: (context, state) {
          final message = _resultMessage(state);
          final rows = state.data ?? [];
          final notices = <Widget>[
            RetainedLoadNotice(
              loading: state.loading,
              error: state.error,
              onRetry: _reload,
            ),
            if (_openedRecord != null &&
                !rows.any((r) => r.name == _openedRecord))
              const Text(
                'The opened record is no longer in this view. The remaining records are shown.',
              ),
          ];
          if (scrollingControls != null) {
            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(child: scrollingControls),
                if (message != null)
                  SliverToBoxAdapter(child: message)
                else ...[
                  SliverToBoxAdapter(
                    child: Column(children: [...notices, _pager(rows)]),
                  ),
                  SliverList.builder(
                    itemCount: rows.length,
                    findChildIndexCallback: (key) {
                      final index = rows.indexWhere(
                        (record) => ValueKey(record.name) == key,
                      );
                      return index < 0 ? null : index;
                    },
                    itemBuilder: (_, index) => Column(
                      key: ValueKey(rows[index].name),
                      children: [
                        _record(rows[index], compact),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }
          return message ??
              Column(
                children: [
                  ...notices,
                  _recordList(rows, compact),
                  const SizedBox(height: 10),
                  _pager(rows),
                ],
              );
        },
      );

  Widget _record(ErpRecord record, bool compact, {Key? key}) {
    final detail = widget.module.amountField == null
        ? record.data['modified']?.toString().split(' ').first ?? '—'
        : record.amount == null
        ? '—'
        : widget.module == ErpModule.manufacturing
        ? [
            record.amount!.toString().replaceFirst(RegExp(r'\.0$'), ''),
            if (record.data['stock_uom'] != null) record.data['stock_uom'],
          ].join(' ')
        : money(record.amount!, record.currency ?? widget.currency);
    final focus = _rowFocus.putIfAbsent(
      record.name,
      () => FocusNode(debugLabel: record.name),
    );
    return Material(
      key: key,
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        focusNode: focus,
        onTap: () {
          widget.model.opened(record.name);
          focus.requestFocus();
          widget.onRecord(record);
        },
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
