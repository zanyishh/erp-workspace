import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../../../core/ui/document_dialogs.dart';
import '../../../core/ui/widgets.dart';
import '../models/invoice_templates.dart';
import 'invoice_gallery.dart';
import 'invoice_settings_view_model.dart';

class InvoiceSettingsView extends StatefulWidget {
  const InvoiceSettingsView({
    super.key,
    required this.model,
    required this.company,
    required this.protect,
  });
  final InvoiceSettingsViewModel model;
  final String company;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<InvoiceSettingsView> createState() => _InvoiceSettingsViewState();
}

class _InvoiceSettingsViewState extends State<InvoiceSettingsView> {
  static const labels = {
    'signatory_name': 'Signatory name',
    'print_footer': 'Printed footer',
    'bank_name': 'Bank name',
    'account_holder': 'Account holder',
    'account_number': 'Account number',
    'ifsc': 'IFSC',
    'upi_id': 'UPI ID',
    'upi_name': 'UPI payee name',
  };
  final form = GlobalKey<FormState>();
  final fields = {for (final key in labels.keys) key: TextEditingController()};
  DialogRoute<bool>? leaveRoute;
  int _seenVersion = -1;
  Object? _seenScope;
  Object get scope => widget.model.scope;
  bool current(Object value) => mounted && widget.model.isCurrent(value);
  bool get busy => widget.model.busy;
  bool get dirty => widget.model.dirty;
  bool get stale => widget.model.stale;
  bool get uncertain => widget.model.uncertain;
  bool get canManage => widget.model.canManage;
  String get style => widget.model.values['template_id'] ?? 'ledger';
  String get logo => widget.model.values['logo_base64'] ?? '';
  String get error => widget.model.error;
  Uint8List? get image => widget.model.image;
  Future<void> get loading => widget.model.loaded;
  void _syncFields() {
    if (_seenVersion != widget.model.draftVersion) {
      _seenVersion = widget.model.draftVersion;
      final values = widget.model.values;
      for (final entry in fields.entries) {
        final value = values[entry.key] ?? '';
        if (entry.value.text != value) entry.value.text = value;
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    _syncFields();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _seenScope = scope;
    widget.model.addListener(_changed);
    _syncFields();
  }

  @override
  void didUpdateWidget(covariant InvoiceSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
      _seenVersion = -1;
      _syncFields();
    }
    if (_seenScope != scope) {
      _seenScope = scope;
      dismissDocumentDialog(leaveRoute);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    dismissDocumentDialog(leaveRoute);
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _reload({bool keepEdits = false}) {
    final future = widget.model.reload(keepEdits: keepEdits);
    setState(() {});
    return future;
  }

  Future<void> _revalidate() {
    final future = widget.model.revalidate();
    setState(() {});
    return future;
  }

  Future<void> _chooseLogo() => widget.model.chooseLogo();
  Future<void> _chooseStyle() async {
    final model = widget.model, captured = model.prepareTemplateChoice();
    if (captured == null) return;
    final selected = await chooseInvoiceTemplate(context, style);
    if (selected != null && mounted && identical(model, widget.model)) {
      model.acceptTemplateChoice(captured, selected.id);
    }
  }

  String? _validate(String key, String raw) =>
      widget.model.validateField(key, raw);
  Future<void> _save() async {
    if (busy || stale || !canManage || !dirty && !uncertain) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(invalid.first.context, alignment: .35);
      return;
    }
    final model = widget.model, captured = model.scope;
    final confirmed = await model.save();
    if (confirmed &&
        mounted &&
        identical(model, widget.model) &&
        model.isCurrent(captured)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _checkSaved() async {
    final model = widget.model, captured = model.scope;
    final confirmed = await model.checkSaved();
    if (confirmed &&
        mounted &&
        identical(model, widget.model) &&
        model.isCurrent(captured)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _leave() async {
    if (busy || leaveRoute != null) return;
    final captured = scope;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard invoice setting changes?'),
        content: uncertain
            ? const Text(
                'The save outcome is not confirmed. Reopen these company settings to inspect their current saved values before making another change.',
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    leaveRoute = route;
    final discard = await Navigator.of(context).push(route);
    leaveRoute = null;
    if (discard == true && mounted && current(captured)) Navigator.pop(context);
  }

  Widget _field(String key) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: fields[key],
      enabled: !busy && !uncertain,
      maxLength: key == 'ifsc' ? 11 : 100,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: key == 'ifsc'
          ? TextCapitalization.characters
          : TextCapitalization.none,
      keyboardType: key == 'upi_id'
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(labelText: labels[key], counterText: ''),
      onChanged: (value) => widget.model.change(key, value),
      validator: (v) => _validate(key, v ?? ''),
    ),
  );

  Widget _panel(String title, IconData icon, List<Widget> children) => Panel(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        ...children,
      ],
    ),
  );

  Widget _appearance() {
    final template = invoiceTemplateById(style);
    return _panel('Appearance', Icons.style_outlined, [
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox(
              width: 100,
              height: 70,
              child: image == null
                  ? const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: WorkspaceTheme.muted,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.memory(
                        image!,
                        fit: BoxFit.contain,
                        cacheWidth: 240,
                        semanticLabel: 'Company logo',
                      ),
                    ),
            ),
          ),
        ),
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: busy || uncertain ? null : _chooseLogo,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: Text(logo.isEmpty ? 'Add logo' : 'Replace logo'),
          ),
          if (logo.isNotEmpty)
            IconButton(
              tooltip: 'Remove logo',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy || uncertain ? null : widget.model.clearLogo,
            ),
        ],
      ),
      Text(
        'PNG or JPEG, up to 2 MB',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const Divider(height: 32),
      Text('Default template', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Tooltip(
        message: 'Choose default template',
        child: OutlinedButton.icon(
          onPressed: busy || uncertain ? null : _chooseStyle,
          icon: const Icon(Icons.style_outlined),
          label: Text(template.name),
        ),
      ),
      if (widget.model.values.containsKey('accent_color')) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey((
            scope,
            template.id,
            widget.model.values['accent_color'],
          )),
          isExpanded: true,
          initialValue: widget.model.values['accent_color'],
          decoration: const InputDecoration(labelText: 'Invoice accent'),
          items: [
            for (final entry in {
              '': 'Use template colors',
              ...invoiceAccentColors,
            }.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(template.printAccent(entry.key)),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 18),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(entry.value)),
                  ],
                ),
              ),
          ],
          onChanged: busy || uncertain
              ? null
              : (value) {
                  if (value != null) widget.model.change('accent_color', value);
                },
        ),
      ],
      for (final key in ['signatory_name', 'print_footer'])
        if (widget.model.values.containsKey(key)) _field(key),
    ]);
  }

  Widget _body() => Form(
    key: form,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final payment = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _panel('Bank transfer', Icons.account_balance_outlined, [
                    for (final k in [
                      'bank_name',
                      'account_holder',
                      'account_number',
                      'ifsc',
                    ])
                      _field(k),
                  ]),
                  const SizedBox(height: 12),
                  _panel('UPI payment QR', Icons.qr_code_2, [
                    const SizedBox(height: 6),
                    const Text(
                      'Customers can scan the code on submitted INR invoices to pay the outstanding amount.',
                    ),
                    _field('upi_id'),
                    _field('upi_name'),
                  ]),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.company,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'These settings apply to invoices for this company, including reprints. Each invoice can keep its own template.',
                  ),
                  const SizedBox(height: 18),
                  if (constraints.maxWidth >= 690 &&
                      MediaQuery.textScalerOf(context).scale(14) < 22)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _appearance()),
                        const SizedBox(width: 14),
                        Expanded(flex: 4, child: payment),
                      ],
                    )
                  else ...[
                    _appearance(),
                    const SizedBox(height: 12),
                    payment,
                  ],
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
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
                  if (uncertain)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : _checkSaved,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Check saved settings'),
                      ),
                    ),
                  if (stale)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Reloading replaces your unsaved changes with the current server settings.',
                      ),
                    ),
                  if (stale)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _reload().catchError((_) {}),
                        child: const Text('Reload settings'),
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

  @override
  Widget build(BuildContext context) => widget.protect(
    PopScope(
      canPop: !dirty && !busy && !uncertain,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && !busy) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Invoice settings')),
        body: SafeArea(
          child: FutureBuilder<void>(
            future: loading,
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (result.hasError) {
                return Center(
                  child: MessagePanel(
                    title: 'Could not load invoice settings',
                    message: result.error.toString(),
                    action: () => _reload().catchError((_) {}),
                  ),
                );
              }
              if (!canManage) {
                return const Center(
                  child: Text('Your company owner manages invoice settings.'),
                );
              }
              return Column(
                children: [
                  Expanded(child: _body()),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: Text(
                            uncertain ? 'Retry same settings' : 'Save settings',
                          ),
                          onPressed: busy || !dirty && !uncertain || stale
                              ? null
                              : _save,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    _revalidate,
  );
}
