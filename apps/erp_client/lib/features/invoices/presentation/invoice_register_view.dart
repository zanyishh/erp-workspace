import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../../../core/ui/retained_load.dart';
import '../../../core/ui/record_identity.dart';
import '../../../core/ui/widgets.dart';
import '../models/invoice_register_page.dart';
import '../models/invoice_templates.dart';
import 'invoice_register_view_model.dart';
import 'invoice_register_row.dart';
import 'invoice_gallery.dart';

enum _Section { invoices, templates }

class InvoiceRegisterView extends StatefulWidget {
  const InvoiceRegisterView({
    super.key,
    required this.model,
    required this.company,
    required this.canCreate,
    this.onImportedHistory,
    this.identityFor,
    this.templateScope,
    required this.gallery,
    required this.openEditor,
    required this.sample,
    required this.preview,
    required this.settings,
    required this.protect,
  });
  final RecordIdentityTransition Function(String)? identityFor;
  final Object? templateScope;
  final InvoiceRegisterViewModel model;
  final String company;
  final bool canCreate;
  final VoidCallback? onImportedHistory;
  final Widget Function(String?, ValueChanged<InvoiceTemplate>) gallery;
  final Future<String?> Function(InvoiceRegisterPage, String?, InvoiceTemplate?)
  openEditor;
  final Future<InvoiceTemplate?> Function(
    InvoiceRegisterPage?,
    InvoiceTemplate,
    bool,
  )
  sample;
  final Future<void> Function(InvoiceRegisterPage, String) preview;
  final Future<bool> Function(InvoiceRegisterPage) settings;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<InvoiceRegisterView> createState() => _InvoiceRegisterViewState();
}

class _InvoiceRegisterViewState extends State<InvoiceRegisterView> {
  String? _openedRecord;
  final _rowFocus = <String, FocusNode>{};
  final search = TextEditingController();
  Timer? debounce;
  var section = _Section.invoices;
  String get query => widget.model.query;
  String get status => widget.model.status;
  int get start => widget.model.start;
  void _resetView() {
    for (final node in _rowFocus.values) {
      node.unfocus();
    }
    debounce?.cancel();
    search.clear();
    section = _Section.invoices;
    _openedRecord = null;
  }

  @override
  void didUpdateWidget(covariant InvoiceRegisterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) _resetView();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _revalidate() async {
    _resetView();
    final future = widget.model.revalidate();
    setState(() {});
    await future;
  }

  void _refresh({bool first = false}) {
    if (first) _openedRecord = null;
    widget.model.reload(first: first);
    setState(() {});
  }

  void _search(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 240), () {
      if (mounted) _searchNow(value);
    });
  }

  void _searchNow(String value) {
    debounce?.cancel();
    _openedRecord = null;
    widget.model.search(value);
    setState(() {});
  }

  void _status(String value) {
    _openedRecord = null;
    widget.model.chooseStatus(value);
    setState(() {});
  }

  void _showAll() {
    debounce?.cancel();
    search.clear();
    _openedRecord = null;
    widget.model.showAll();
    setState(() {});
  }

  Future<void> _openEditor(
    InvoiceRegisterPage page, [
    String? name,
    InvoiceTemplate? template,
  ]) async {
    final model = widget.model, scope = widget.model.scope;
    if (name == null
        ? !widget.canCreate || !model.canCreate(page)
        : !model.canOpen(page, name)) {
      return;
    }
    _openedRecord = name;
    _rowFocus[name]?.requestFocus();
    debounce?.cancel();
    final created = await widget.openEditor(page, name, template);
    if (!mounted ||
        !identical(model, widget.model) ||
        !model.isCurrent(scope)) {
      return;
    }
    if (created != null) {
      // A backdated draft can fall outside the first page of the register.
      search.value = TextEditingValue(
        text: created,
        selection: TextSelection.collapsed(offset: created.length),
      );
      section = _Section.invoices;
      _openedRecord = null;
      model.showAll(query: created);
      setState(() {});
    } else {
      _refresh();
    }
  }

  Future<void> _sample(
    InvoiceRegisterPage? page,
    InvoiceTemplate template,
    bool canCreate,
  ) async {
    final model = widget.model, scope = model.scope;
    final chosen = await widget.sample(page, template, canCreate);
    if (chosen != null &&
        mounted &&
        identical(model, widget.model) &&
        model.isCurrent(scope)) {
      final currentPage = model.loadedPage;
      if (currentPage != null && model.canCreate(currentPage)) {
        await _openEditor(currentPage, null, chosen);
      }
    }
  }

  Future<void> _preview(InvoiceRegisterPage page, Map row) async {
    final name = row['name'] as String;
    if (!widget.model.canOpen(page, name)) return;
    if (row['can_print'] != true) {
      await _openEditor(page, name);
      return;
    }
    await widget.preview(page, name);
  }

  Future<void> _settings(InvoiceRegisterPage page) async {
    final model = widget.model, scope = model.scope;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final saved = await widget.settings(page);
    if (!mounted ||
        !identical(model, widget.model) ||
        !model.isCurrent(scope) ||
        !saved) {
      return;
    }
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invoice settings saved for ${widget.company}.')),
    );
  }

  bool _compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 690 ||
      MediaQuery.textScalerOf(context).scale(14) > 20;

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: AppBar(
        title: Text(
          _compact(context) ? 'Invoices' : widget.company,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.onImportedHistory != null)
            if (MediaQuery.sizeOf(context).width < 600)
              IconButton(
                onPressed: widget.onImportedHistory,
                icon: const Icon(Icons.history_outlined),
                tooltip: 'Imported invoices',
              )
            else
              TextButton.icon(
                onPressed: widget.onImportedHistory,
                icon: const Icon(Icons.history_outlined),
                label: const Text('Imported invoices'),
              ),
          if (section == _Section.invoices)
            IconButton(
              tooltip: 'Refresh invoices',
              onPressed: () => _refresh(),
              icon: const Icon(Icons.refresh_outlined),
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    ),
    _revalidate,
  );

  Widget _body() => RetainedFutureBuilder<InvoiceRegisterPage>(
    future: widget.model.result,
    scope: widget.model.viewScope,
    builder: (context, state) {
      final page = widget.model.canUse(state.data) ? state.data : null;
      final data = page?.data;
      final canCreate = widget.canCreate && widget.model.canCreate(page);
      return LayoutBuilder(
        builder: (context, box) {
          final pad = box.maxWidth >= 700 ? 26.0 : 14.0;
          final compact = _compact(context);
          final controls = [
            _heading(page, pad, compact, canCreate),
            _tabs(box, pad),
            if (section == _Section.invoices) _filters(data, pad, compact),
          ];
          final content = section == _Section.templates
              ? widget.gallery(
                  data?['default_template_id'] as String?,
                  (t) => _sample(page, t, canCreate),
                )
              : _registerBody(state, page, pad, compact, canCreate, box);
          if (compact) {
            return NestedScrollView(
              headerSliverBuilder: (_, _) => [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: controls,
                  ),
                ),
              ],
              body: content,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...controls,
              Expanded(child: content),
            ],
          );
        },
      );
    },
  );

  Widget _heading(
    InvoiceRegisterPage? page,
    double pad,
    bool compact,
    bool canCreate,
  ) => Padding(
    padding: EdgeInsets.fromLTRB(pad, 6, pad, 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        if (compact)
          Text(widget.company, style: Theme.of(context).textTheme.titleMedium)
        else
          Semantics(
            headingLevel: 1,
            child: const Display('Invoices', size: 48),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (widget.model.canManageSettings(page))
              Tooltip(
                message: 'Invoice settings',
                child: OutlinedButton.icon(
                  onPressed: () => _settings(page!),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Invoice settings'),
                ),
              ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () => _openEditor(page!),
                icon: const Icon(Icons.add),
                label: const Text('New invoice'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _tabs(BoxConstraints box, double pad) => Padding(
    padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child:
          (box.maxWidth < 450 &&
              MediaQuery.textScalerOf(context).scale(14) > 16)
          ? Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final tab in _Section.values)
                  ChoiceChip(
                    selected: section == tab,
                    showCheckmark: false,
                    label: Text(
                      tab == _Section.invoices ? 'Sales invoices' : 'Templates',
                    ),
                    onSelected: (_) => setState(() => section = tab),
                  ),
              ],
            )
          : SegmentedButton<_Section>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _Section.invoices,
                  icon: Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('Sales invoices'),
                ),
                ButtonSegment(
                  value: _Section.templates,
                  icon: Icon(Icons.style_outlined, size: 18),
                  label: Text('Templates'),
                ),
              ],
              selected: {section},
              onSelectionChanged: (value) =>
                  setState(() => section = value.first),
            ),
    ),
  );

  Widget _filters(Map<String, dynamic>? data, double pad, bool compact) =>
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                maxLength: 140,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _searchNow(v);
                },
                decoration: InputDecoration(
                  counterText: '',
                  prefixIcon: const Icon(Icons.search, size: 19),
                  hintText: compact
                      ? 'Search invoices'
                      : 'Search invoice number or customer',
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: search,
                    builder: (context, text, _) => text.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear, size: 17),
                            onPressed: () {
                              debounce?.cancel();
                              search.clear();
                              _searchNow('');
                            },
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Filter invoice status',
              onSelected: (v) {
                _status(v);
              },
              itemBuilder: (_) => [
                for (final v in (data?['statuses'] as List? ?? [status]))
                  CheckedPopupMenuItem(
                    value: v.toString(),
                    checked: status == v,
                    child: Text(
                      v.toString() == 'All' ? 'All statuses' : v.toString(),
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 48,
                  maxWidth: compact ? 110 : 230,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune, size: 17),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        status == 'All' ? 'Status' : status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _registerBody(
    RetainedLoad<InvoiceRegisterPage> state,
    InvoiceRegisterPage? page,
    double pad,
    bool compact,
    bool canCreate,
    BoxConstraints box,
  ) {
    final data = page?.data;
    return data == null && !state.hasError
        ? const Center(child: CircularProgressIndicator())
        : state.hasError && data == null
        ? Center(
            child: MessagePanel(
              title: 'Could not load invoices',
              message: state.error.toString(),
              action: () => _refresh(),
            ),
          )
        : Column(
            children: [
              RetainedLoadNotice(
                loading: state.loading,
                error: state.error,
                onRetry: _refresh,
              ),
              if (_openedRecord != null &&
                  !(data!['rows'] as List).any(
                    (r) => r['name'] == _openedRecord,
                  ))
                const Text(
                  'The opened invoice is no longer in this view. The remaining invoices are shown.',
                ),
              Expanded(
                child: _listWithTemplates(page!, pad, compact, canCreate, box),
              ),
            ],
          );
  }

  Widget _listWithTemplates(
    InvoiceRegisterPage page,
    double pad,
    bool compact,
    bool canCreate,
    BoxConstraints box,
  ) {
    final list = _rows(page, pad, compact, canCreate);
    if (box.maxWidth < 1080 ||
        box.maxHeight < 460 ||
        MediaQuery.textScalerOf(context).scale(14) > 20) {
      return list;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        SizedBox(
          width: 230,
          child: Padding(
            padding: const EdgeInsets.only(right: 26, bottom: 14),
            child: Material(
              color: WorkspaceTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: WorkspaceTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  const Display('Print templates', size: 23),
                  const SizedBox(height: 12),
                  for (final id in ['canopy', 'ledger'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () =>
                            _sample(page, invoiceTemplateById(id), canCreate),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ColoredBox(
                              color: const Color(0xffdeded9),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 12,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 210 / 297,
                                  child: InvoicePaperContinuity(
                                    tag: widget.templateScope == null
                                        ? null
                                        : (widget.templateScope, id),
                                    template: invoiceTemplateById(id),
                                    child: Image.asset(
                                      invoiceTemplateById(id).thumbnailAsset,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                invoiceTemplateById(id).name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () =>
                        setState(() => section = _Section.templates),
                    child: Text(
                      'View all ${invoiceTemplates.length} templates',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rows(
    InvoiceRegisterPage page,
    double pad,
    bool compact,
    bool canCreate,
  ) {
    final rows = page.rows;
    final more = page.hasMore;
    if (rows.isEmpty) {
      final filtered = status != 'All' || query.isNotEmpty || start > 0;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: WorkspaceTheme.muted,
              ),
              const SizedBox(height: 12),
              Text(
                _openedRecord != null
                    ? 'The opened invoice is no longer in this view'
                    : filtered
                    ? 'No matching invoices'
                    : 'No sales invoices yet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (filtered)
                TextButton(
                  onPressed: () {
                    debounce?.cancel();
                    search.clear();
                    _showAll();
                  },
                  child: const Text('Show all invoices'),
                )
              else if (canCreate)
                OutlinedButton(
                  onPressed: () => _openEditor(page),
                  child: const Text('Create your first invoice'),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: WorkspaceTheme.surface,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: WorkspaceTheme.border),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                key: ValueKey((query, status, start)),
                itemCount: rows.length + (compact ? 0 : 1),
                findItemIndexCallback: (key) {
                  final index = rows.indexWhere(
                    (row) => key is ValueKey && key.value == row['name'],
                  );
                  return index < 0 ? null : index + (compact ? 0 : 1);
                },
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (!compact && index == 0) {
                    return const InvoiceRegisterColumns(
                      identity: Text('Invoice / customer'),
                      issued: Text('Issued'),
                      status: Text('Status'),
                      total: Text('Total', textAlign: TextAlign.right),
                    );
                  }
                  final row = rows[index - (compact ? 0 : 1)];
                  return InvoiceRegisterRow(
                    key: ValueKey(row['name']),
                    identity: widget.identityFor?.call(row['name'] as String),
                    focusNode: _rowFocus.putIfAbsent(
                      row['name'].toString(),
                      () => FocusNode(debugLabel: row['name'].toString()),
                    ),
                    row: row,
                    compact: compact,
                    onOpen: () => _openEditor(page, row['name'] as String),
                    onPreview: () => _preview(page, row),
                  );
                },
              ),
            ),
          ),
          if (start > 0 || more)
            Row(
              children: [
                Expanded(
                  child: Text('Showing ${start + 1}–${start + rows.length}'),
                ),
                IconButton(
                  tooltip: 'Previous invoices',
                  onPressed: start == 0
                      ? null
                      : () {
                          widget.model.previousPage();
                          setState(() {});
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next invoices',
                  onPressed: more
                      ? () {
                          widget.model.nextPage();
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
