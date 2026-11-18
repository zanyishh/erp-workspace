import 'package:flutter/material.dart';

import '../../../core/models/native_models.dart' show objectMap;
import '../../../core/ui/design.dart';
import '../../../core/ui/workspace_ui.dart';
import '../models/invoice_compose.dart';
import '../models/invoice_number.dart';
import '../models/invoice_templates.dart';
import 'invoice_composer_view_model.dart';

typedef InvoiceLinkFieldBuilder = Widget Function(
  String type,
  String label,
  String value,
  ValueChanged<String> change, {
  FocusNode? focusNode,
  VoidCallback? onCommitted,
  String? error,
  required bool editable,
  required Object scope,
  required Future<List<Map<String, dynamic>>> Function(String, String) search,
});

class InvoiceComposerView extends StatefulWidget {
  const InvoiceComposerView({
    super.key,
    required this.model,
    required this.linkField,
    required this.openEditor,
    required this.protect,
    this.continueToEditor = false,
  });
  final InvoiceComposerViewModel model;
  final InvoiceLinkFieldBuilder linkField;
  final Future<String?> Function({String? name}) openEditor;
  final Widget Function(Widget, Future<void> Function()) protect;
  final bool continueToEditor;
  @override
  State<InvoiceComposerView> createState() => _ComposerState();
}

class _LineFocus {
  final item = FocusNode(), qty = FocusNode(), rate = FocusNode();
  void dispose() {
    item.dispose();
    qty.dispose();
    rate.dispose();
  }
}

class _ComposerState extends State<InvoiceComposerView> {
  final _focuses = <Object, _LineFocus>{};
  final customerFocus = FocusNode();
  final _dueCorrectionFocus = FocusNode(), _addItemFocus = FocusNode();
  final _scroll = ScrollController();
  final _summary = GlobalKey();
  Route<dynamic>? dialog;
  bool askingLeave = false;
  late Object _observedScope;
  InvoiceComposerViewModel get model => widget.model;
  List<InvoiceDraftLine> get lines => model.lines;
  String get customer => model.customer;
  String get posting => model.posting;
  String get due => model.due;
  String get style => model.style;
  String get companyStyle => model.companyStyle;
  String get error => model.error;
  bool get editable => model.editable;
  bool get busy => model.busy;
  bool get uncertain => model.uncertain;
  bool get prepared => model.prepared;
  bool get showErrors => model.showErrors;
  Map<String, dynamic>? get quote => model.reviewed?.data;
  _LineFocus _focusFor(Object id) => _focuses.putIfAbsent(id, _LineFocus.new);
  @override
  void initState() {
    super.initState();
    _observedScope = model.scope;
    model.addListener(_changed);
  }

  void _dismissDialog({bool afterFrame = false}) {
    final route = dialog;
    dialog = null;
    void remove() {
      if (route != null && route.isActive && route.navigator?.mounted == true) {
        route.navigator!.removeRoute(route);
      }
    }

    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_observedScope != model.scope) {
      _observedScope = model.scope;
      _dismissDialog();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant InvoiceComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != model) {
      oldWidget.model.removeListener(_changed);
      model.addListener(_changed);
    }
    if (oldWidget.model != model || _observedScope != model.scope) {
      _observedScope = model.scope;
      _dismissDialog();
    }
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    _dismissDialog(afterFrame: true);
    customerFocus.dispose();
    _dueCorrectionFocus.dispose();
    _addItemFocus.dispose();
    _scroll.dispose();
    for (final focus in _focuses.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<T?> scopedDialog<T>(WidgetBuilder builder) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    dialog = route;
    final value = await Navigator.of(context).push(route);
    if (dialog == route) dialog = null;
    return value;
  }

  Future<void> leave() async {
    final owner = model, captured = model.scope, state = model.leaveState;
    if (state == InvoiceLeaveState.busy || askingLeave) return;
    if (state == InvoiceLeaveState.blocked) {
      owner.explainBlockedLeave();
      return;
    }
    if (state == InvoiceLeaveState.free) {
      Navigator.pop(context);
      return;
    }
    askingLeave = true;
    final pending = state == InvoiceLeaveState.pending;
    final yes = await scopedDialog<bool>(
      (c) => AlertDialog(
        title: Text(
          pending ? 'Check this save later?' : 'Discard invoice changes?',
        ),
        content: Text(
          pending
              ? 'The request reference is saved in Pending operations for ${owner.company}. Check it there before creating another invoice.'
              : 'Your unsaved invoice changes will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(pending ? 'Leave and check later' : 'Discard changes'),
          ),
        ],
      ),
    );
    askingLeave = false;
    if (mounted &&
        identical(owner, model) &&
        owner.canConfirmLeave(captured) &&
        yes == true) {
      Navigator.pop(context);
    }
  }

  void removeLine(InvoiceDraftLine row) {
    final owner = model, removed = model.removeLine(row.id);
    if (removed == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Invoice item removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted && identical(owner, model)) owner.restoreLine(removed);
          },
        ),
      ),
    );
  }

  void _focusInvalid() {
    FocusNode? first;
    if (customer.trim().isEmpty) {
      first = customerFocus;
    } else if (model.dueBeforeInvoice) {
      first = _dueCorrectionFocus;
    } else if (lines.isEmpty) {
      first = _addItemFocus;
    }
    for (final row in lines) {
      final focus = _focusFor(row.id);
      first ??= row.item.trim().isEmpty
          ? focus.item
          : !validInvoiceNumber(row.qty, positive: true)
          ? focus.qty
          : row.rate.trim().isNotEmpty && !validInvoiceNumber(row.rate)
          ? focus.rate
          : null;
    }
    if (first != null) _revealField(first);
  }

  Future<void> _revealField(FocusNode field) async {
    final owner = model, scope = model.scope;
    bool current() =>
        mounted && identical(owner, model) && model.isCurrent(scope);
    await WidgetsBinding.instance.endOfFrame;
    if (!current() || !_scroll.hasClients) return;
    // A long invoice can have invalid lines outside the ListView's build cache.
    if (field.context?.mounted != true) {
      _scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
      while (current() &&
          _scroll.hasClients &&
          field.context?.mounted != true) {
        final position = _scroll.position;
        final next = (position.pixels + position.viewportDimension)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble();
        if (next <= position.pixels) return;
        _scroll.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    final fieldContext = field.context;
    if (!mounted ||
        !current() ||
        fieldContext == null ||
        !fieldContext.mounted) {
      return;
    }
    field.requestFocus();
    await Scrollable.ensureVisible(
      fieldContext,
      duration: workspaceMotion(context),
      alignment: .2,
    );
  }

  void _addLine() {
    model.addLine();
    _revealField(_focusFor(lines.last.id).item);
  }

  Future<void> review({bool showSummary = true}) async {
    if (!editable) return;
    if (!model.validate()) {
      _focusInvalid();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final owner = model, scope = model.scope;
    final success = await owner.review();
    if (!success || !showSummary) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !identical(model, owner) ||
        !model.isCurrent(scope) ||
        quote == null ||
        !_scroll.hasClients) {
      return;
    }
    final summaryContext = _summary.currentContext;
    if (summaryContext != null && summaryContext.mounted) {
      await Scrollable.ensureVisible(
        summaryContext,
        duration: workspaceMotion(context),
      );
    } else {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  String money(Object? v, int precision) => formatInvoiceNumber(
    v,
    places: precision,
    indian: quote?['currency'] == 'INR',
  );
  Future<void> save({bool advanced = false}) async {
    final owner = model, receipt = await model.save();
    if (receipt != null && mounted && identical(owner, model)) {
      await saved(owner, receipt, advanced: advanced);
    }
  }

  Future<void> saved(
    InvoiceComposerViewModel owner,
    InvoiceDraftReceipt receipt, {
    bool advanced = false,
  }) async {
    if (!mounted || !identical(owner, model) || !owner.canUse(receipt)) return;
    final confirmation = ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Draft ${receipt.name} saved.')));
    // Keep the confirmation owner alive until its receipt has reached a frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !identical(owner, model) || !owner.canUse(receipt)) {
      confirmation.close();
      return;
    }
    owner.acknowledge(receipt);
    if (advanced) await widget.openEditor(name: receipt.name);
    if (mounted && identical(owner, model) && owner.canUse(receipt)) {
      Navigator.pop(context, receipt.name);
    }
  }

  Future<void> checkSave({bool close = false}) async {
    final owner = model, receipt = await model.checkSave(close: close);
    if (receipt != null && mounted && identical(owner, model)) {
      await saved(owner, receipt, advanced: widget.continueToEditor);
    }
  }

  Widget link(
    String type,
    String label,
    String value,
    ValueChanged<String> change, {
    FocusNode? focusNode,
    VoidCallback? onCommitted,
    String? fieldError,
  }) => widget.linkField(
    type,
    label,
    value,
    change,
    focusNode: focusNode,
    onCommitted: onCommitted,
    error: fieldError,
    editable: editable,
    scope: model.scope,
    search: model.searchLinks,
  );
  Future<void> pickDate(bool forDue) async {
    if (!editable) return;
    final owner = model, captured = model.scope;
    final invoiceDate = DateTime.tryParse(posting);
    final first = forDue && invoiceDate != null ? invoiceDate : DateTime(1900);
    final selected =
        DateTime.tryParse(forDue ? due : posting) ??
        invoiceDate ??
        DateTime.now();
    final start = selected.isBefore(first) ? first : selected;
    final d = await showDatePicker(
      context: context,
      builder: (c, child) {
        dialog = ModalRoute.of(c);
        return child!;
      },
      initialDate: start,
      firstDate: first,
      lastDate: DateTime(2200),
    );
    dialog = null;
    if (d != null &&
        mounted &&
        identical(owner, model) &&
        owner.isCurrent(captured)) {
      owner.changeDate(d.toIso8601String().split('T').first, due: forDue);
    }
  }

  Future<void> advanced() async {
    if (!editable) return;
    final owner = model, captured = model.scope;
    if (model.hasEdits) {
      if (quote == null) await review(showSummary: false);
      if (!mounted ||
          !identical(owner, model) ||
          !owner.isCurrent(captured) ||
          quote == null) {
        return;
      }
      final reviewedTotal = _reviewedTotal(quote!);
      final yes = await scopedDialog<bool>(
        (c) => AlertDialog(
          title: const Text('Save draft and open full editor?'),
          content: Text(
            'The draft will use the reviewed total of $reviewedTotal. You can then edit taxes, payment terms and other invoice fields.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save and open'),
            ),
          ],
        ),
      );
      if (yes == true &&
          mounted &&
          identical(owner, model) &&
          owner.isCurrent(captured)) {
        await save(advanced: true);
      }
      return;
    }
    final name = await widget.openEditor();
    if (!mounted ||
        name == null ||
        !identical(owner, model) ||
        !owner.isCurrent(captured)) {
      return;
    }
    final receipt = await owner.completeAdvanced(name, captured);
    if (!mounted ||
        !identical(owner, model) ||
        receipt == null ||
        !owner.canUse(receipt)) {
      return;
    }
    if (receipt.warning != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(receipt.warning!)));
    }
    Navigator.pop(context, receipt.name);
  }

  static const _numbers = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _surface({Key? key, required List<Widget> children}) => Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: WorkspaceTheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: WorkspaceTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  // Share the customer/date and item/amount split across the invoice.
  Widget _columns(Widget first, Widget second, {double breakpoint = 600}) =>
      LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (box.maxWidth < breakpoint * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 12), second],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          );
        },
      );

  Widget rowEditor(List<InvoiceDraftLine> draftLines, int idx) {
    final row = draftLines[idx];
    final focus = _focusFor(row.id);
    final owner = model, scope = model.scope;
    final nextLine = idx + 1 < draftLines.length ? draftLines[idx + 1] : null;
    final checked = quote;
    final reviewed = checked == null
        ? null
        : objectMap((checked['items'] as List)[idx]);
    final quantity = TextFormField(
      key: const ValueKey('quantity'),
      initialValue: row.qty,
      focusNode: focus.qty,
      enabled: editable,
      textAlign: TextAlign.end,
      style: _numbers,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onEditingComplete: () => _revealField(focus.rate),
      decoration: InputDecoration(
        labelText: 'Quantity',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorMaxLines: 3,
        errorText: showErrors
            ? invoiceNumberError(row.qty, positive: true)
            : null,
      ),
      onChanged: (v) => model.changeLine(row.id, qty: v),
    );
    final rate = TextFormField(
      key: const ValueKey('rate'),
      initialValue: row.rate,
      focusNode: focus.rate,
      enabled: editable,
      textAlign: TextAlign.end,
      style: _numbers,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: nextLine == null
          ? TextInputAction.done
          : TextInputAction.next,
      onEditingComplete: nextLine == null
          ? null
          : () => _revealField(_focusFor(nextLine.id).item),
      decoration: InputDecoration(
        labelText: 'Rate override',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: 'Price list',
        errorMaxLines: 3,
        errorText: showErrors && row.rate.trim().isNotEmpty
            ? invoiceNumberError(row.rate)
            : null,
      ),
      onChanged: (v) => model.changeLine(row.id, rate: v),
    );
    return _surface(
      key: ObjectKey(row.id),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Item ${idx + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            if (draftLines.length > 1)
              PopupMenuButton<bool>(
                tooltip: 'Move item ${idx + 1}',
                enabled: editable,
                icon: const Icon(Icons.swap_vert),
                onSelected: (up) {
                  if (mounted &&
                      identical(model, owner) &&
                      owner.isCurrent(scope)) {
                    owner.moveLine(row.id, up: up);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: true,
                    enabled: idx > 0,
                    child: const Text('Move up'),
                  ),
                  PopupMenuItem(
                    value: false,
                    enabled: nextLine != null,
                    child: const Text('Move down'),
                  ),
                ],
              ),
            IconButton(
              tooltip: 'Remove item ${idx + 1}',
              onPressed: editable ? () => removeLine(row) : null,
              icon: const Icon(
                Icons.delete_outline,
                size: 19,
                color: WorkspaceTheme.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _columns(
          link(
            'Item',
            'Item or service',
            row.item,
            (s) => model.changeLine(row.id, item: s),
            onCommitted: () => _revealField(focus.qty),
            focusNode: focus.item,
            fieldError: showErrors && row.item.trim().isEmpty
                ? 'Choose an item or service.'
                : null,
          ),
          _columns(quantity, rate, breakpoint: 286),
        ),
        if (checked != null && reviewed != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${formatInvoiceNumber(reviewed['qty'])} ${reviewed['uom'] ?? ''} × ${formatInvoiceNumber(reviewed['rate'])}',
                  style: _numbers.copyWith(color: WorkspaceTheme.muted),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "${checked['currency']} ${money(reviewed['amount'], checked['precision'])}",
                    style: _numbers.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dateField(String label, String value, {required bool forDue}) =>
      TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: editable ? () => pickDate(forDue) : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            enabled: editable,
            filled: false,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );

  List<Widget> _draftFields(bool compact) {
    final checked = quote;
    final dueFields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateField(
          'Due date',
          due.isEmpty
              ? (checked?['due_date']?.toString() ?? 'Customer terms')
              : due,
          forDue: true,
        ),
        if (due.isNotEmpty)
          TextButton(
            onPressed: editable ? () => model.changeDate('', due: true) : null,
            child: const Text('Use customer terms'),
          ),
      ],
    );
    final template = DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: style,
      decoration: const InputDecoration(labelText: 'Print template'),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            companyStyle.isEmpty
                ? 'Company default'
                : 'Company default · $companyStyle',
          ),
        ),
        for (final t in invoiceTemplates)
          DropdownMenuItem(value: t.id, child: Text(t.name)),
      ],
      onChanged: editable ? (v) => model.changeStyle(v!) : null,
    );
    final details = _columns(dueFields, template);
    final draftLines = lines;
    return [
      _surface(
        children: [
          Text(
            'From',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: WorkspaceTheme.muted),
          ),
          const SizedBox(height: 2),
          Semantics(
            header: true,
            child: Text(
              model.company,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 18),
          _columns(
            link(
              'Customer',
              'Customer',
              customer,
              model.changeCustomer,
              focusNode: customerFocus,
              onCommitted: () => _revealField(
                draftLines.isEmpty
                    ? _addItemFocus
                    : _focusFor(draftLines.first.id).item,
              ),
              fieldError: showErrors && customer.trim().isEmpty
                  ? 'Choose a customer.'
                  : null,
            ),
            _dateField(
              'Invoice date',
              posting.isEmpty ? 'Choose date' : posting,
              forDue: false,
            ),
          ),
          if (model.dueBeforeInvoice)
            TextButton.icon(
              focusNode: _dueCorrectionFocus,
              onPressed: editable ? () => pickDate(true) : null,
              icon: const Icon(Icons.event_outlined),
              label: const Text(
                'Change due date · It must be on or after the invoice date.',
              ),
            ),
          if (posting.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Choose an invoice date to continue.'),
            ),
        ],
      ),
      for (var i = 0; i < draftLines.length; i++) rowEditor(draftLines, i),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          focusNode: _addItemFocus,
          onPressed: editable && draftLines.length < 100 ? _addLine : null,
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ),
      const SizedBox(height: 12),
      _surface(
        children: [
          if (compact)
            ExpansionTile(
              key: const PageStorageKey('invoice-details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('More details'),
              children: [details],
            )
          else
            details,
        ],
      ),
    ];
  }

  Widget _reviewSummary(Map<String, dynamic> checked) => _surface(
    key: _summary,
    children: [
      Semantics(
        header: true,
        child: Text(
          'Invoice summary',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      for (final (label, value) in model.reviewed!.summaryTotals)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: label == 'Total'
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "${checked['currency']} ${money(value, checked['precision'])}",
                    textAlign: TextAlign.end,
                    style: label == 'Total'
                        ? _numbers.copyWith(fontWeight: FontWeight.w700)
                        : _numbers,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  String _reviewedTotal(Map<String, dynamic> checked) =>
      "${checked['currency']} ${money(model.reviewed!.summaryTotals.last.$2, checked['precision'])}";

  Widget? _keypadAction() {
    if (!editable ||
        Theme.of(context).platform != TargetPlatform.iOS ||
        MediaQuery.viewInsetsOf(context).bottom == 0) {
      return null;
    }
    final draftLines = lines;
    for (var i = 0; i < draftLines.length; i++) {
      final focus = _focuses[draftLines[i].id];
      if (focus == null) continue;
      if (focus.qty.hasPrimaryFocus) {
        return IconButton(
          tooltip: 'Next field, rate',
          onPressed: () => _revealField(focus.rate),
          icon: const Icon(Icons.arrow_forward),
        );
      }
      if (focus.rate.hasPrimaryFocus) {
        if (i + 1 == draftLines.length) {
          return IconButton(
            tooltip: 'Dismiss keyboard',
            onPressed: () => focus.rate.unfocus(),
            icon: const Icon(Icons.keyboard_hide_outlined),
          );
        }
        final next = draftLines[i + 1];
        return IconButton(
          tooltip: 'Next item',
          onPressed: () => _revealField(_focusFor(next.id).item),
          icon: const Icon(Icons.arrow_forward),
        );
      }
    }
    return null;
  }

  Widget _footer(bool compact, double height) {
    final checked = quote;
    final Widget action;
    if (uncertain && prepared) {
      action = FilledButton(
        onPressed: busy ? null : checkSave,
        child: const Text('Check save status'),
      );
    } else if (checked != null) {
      action = FilledButton.icon(
        onPressed: busy ? null : () => save(advanced: widget.continueToEditor),
        icon: const Icon(Icons.save_outlined),
        label: Text(
          uncertain
              ? 'Retry same save'
              : widget.continueToEditor
              ? 'Save and open invoice'
              : 'Save draft',
        ),
      );
    } else {
      action = FilledButton(
        onPressed: editable && posting.isNotEmpty ? review : null,
        child: const Text('Review invoice'),
      );
    }
    final count = lines.length;
    final total = checked == null ? null : _reviewedTotal(checked);
    final keypadAction = _keypadAction();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: WorkspaceTheme.surface,
        border: Border(top: BorderSide(color: WorkspaceTheme.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 24,
          vertical: height < 280 ? 4 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (error.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (height * .2).clamp(20.0, 96.0).toDouble(),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
            if (keypadAction != null)
              Row(
                children: [
                  keypadAction,
                  const SizedBox(width: 12),
                  Expanded(child: action),
                ],
              )
            else if (compact &&
                (height < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18))
              action
            else
              Row(
                children: [
                  Expanded(
                    child: total == null
                        ? Text('$count ${count == 1 ? 'item' : 'items'}')
                        : Text(
                            'Total · $total',
                            style: _numbers.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: action,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.protect(
    PopScope(
      canPop: model.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New sales invoice'),
          actions: [
            TextButton(
              onPressed: editable ? advanced : null,
              child: const Text('Full editor'),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxWidth < 600;
                  final checked = quote;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            compact ? 14 : 24,
                            12,
                            compact ? 14 : 24,
                            0,
                          ),
                          children: [
                            ..._draftFields(compact),
                            if (checked != null) _reviewSummary(checked),
                            if (uncertain && prepared)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => checkSave(close: true),
                                child: const Text('Close unposted request'),
                              ),
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: FocusManager.instance,
                        builder: (_, _) => _footer(compact, box.maxHeight),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
    model.revalidate,
  );
}
