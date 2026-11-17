import 'package:flutter/material.dart';

import '../../document_editor.dart';
import '../../erp_api.dart' show ErpApi;
import '../../invoice_composer.dart';
import '../../imported_history.dart';
import '../../features/invoices/presentation/invoice_gallery.dart';
import 'invoice_preview.dart';
import 'invoice_settings.dart';
import '../../features/invoices/data/erp_invoice_repository.dart';
import '../../features/invoices/models/invoice_register_page.dart';
import '../../features/invoices/models/invoice_templates.dart';
import '../../features/invoices/presentation/invoice_register_view.dart';
import '../../features/invoices/presentation/invoice_register_view_model.dart';
import '../gates/access_gate.dart';

class InvoiceHub extends StatefulWidget {
  const InvoiceHub({
    super.key,
    required this.api,
    required this.company,
    required this.canCreate,
    this.onImportedHistory,
  });
  final ErpApi api;
  final String company;
  final bool canCreate;
  final VoidCallback? onImportedHistory;
  @override
  State<InvoiceHub> createState() => _InvoiceHubState();
}

class _InvoiceHubState extends State<InvoiceHub> {
  late ErpInvoiceRepository _repository;
  late InvoiceRegisterViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership =>
      (widget.api, widget.api.baseUri, widget.api.account, widget.company);
  void _create() {
    _owned = _ownership;
    _repository = ErpInvoiceRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = InvoiceRegisterViewModel(_repository);
  }

  @override
  void initState() {
    super.initState();
    _create();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) return;
    if (_owned != _ownership) {
      _model.dispose();
      _create();
      setState(() {});
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant InvoiceHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeAccessListener(_accessChanged);
      widget.api.addAccessListener(_accessChanged);
    }
    if (_owned != _ownership) {
      _model.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    _model.dispose();
    super.dispose();
  }

  bool _current(InvoiceRegisterViewModel model, Object scope) =>
      mounted && identical(model, _model) && model.isCurrent(scope);
  Future<String?> _openEditor(
    InvoiceRegisterPage page,
    String? name,
    InvoiceTemplate? template,
  ) async {
    final model = _model,
        scope = model.scope,
        api = widget.api,
        company = widget.company;
    if (name == null
        ? !widget.canCreate || !model.canCreate(page)
        : !model.canOpen(page, name)) {
      return null;
    }
    String? result;
    if (name == null) {
      result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceComposer(
            api: api,
            company: company,
            templateId: template?.id,
          ),
        ),
      );
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditor(
            api: api,
            company: company,
            doctype: 'Sales Invoice',
            name: name,
          ),
        ),
      );
    }
    return _current(model, scope) ? result : null;
  }

  Future<InvoiceTemplate?> _sample(
    InvoiceRegisterPage? page,
    InvoiceTemplate template,
    bool canCreate,
  ) async {
    final model = _model,
        scope = model.scope,
        api = widget.api,
        company = widget.company;
    if (!model.isCurrent(scope)) return null;
    final chosen = await Navigator.push<InvoiceTemplate>(
      context,
      MaterialPageRoute(
        builder: (routeContext) => InvoicePreviewScreen(
          api: api,
          company: company,
          initialTemplate: template,
          transitionTag: (
            (api.baseUri, api.account, company, 'invoice-sample'),
            template.id,
          ),
          onCreate:
              canCreate && widget.canCreate && model.canCreate(model.loadedPage)
              ? (style) => Navigator.pop(routeContext, style)
              : null,
        ),
      ),
    );
    return _current(model, scope) &&
            widget.canCreate &&
            model.canCreate(model.loadedPage)
        ? chosen
        : null;
  }

  Future<void> _preview(InvoiceRegisterPage page, String name) async {
    final model = _model, api = widget.api, company = widget.company;
    if (!model.canOpen(page, name, preview: true)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InvoicePreviewScreen(api: api, company: company, invoice: name),
      ),
    );
  }

  Future<bool> _settings(InvoiceRegisterPage page) async {
    final model = _model,
        scope = model.scope,
        api = widget.api,
        company = widget.company;
    if (!model.canManageSettings(page)) return false;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceSettingsScreen(api: api, company: company),
      ),
    );
    return _current(model, scope) &&
        model.canManageSettings(model.loadedPage) &&
        saved == true;
  }

  void _openHistory() {
    if (!widget.api.accessReady ||
        widget.api.contextFor(widget.company)?.canReadImportedHistory != true) {
      return;
    }
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportedHistoryScreen(
          api: api,
          company: company,
          initialFamily: 'invoice',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => InvoiceRegisterView(
    model: _model,
    company: widget.company,
    canCreate: widget.canCreate,
    onImportedHistory:
        widget.onImportedHistory ??
        (widget.api.contextFor(widget.company)?.canReadImportedHistory == true
            ? _openHistory
            : null),
    openEditor: _openEditor,
    sample: _sample,
    preview: _preview,
    settings: _settings,
    gallery: (selected, onChoose) => InvoiceGallery(
      selectedId: selected,
      companyDefault: true,
      transitionScope: (
        widget.api.baseUri,
        widget.api.account,
        widget.company,
        'invoice-sample',
      ),
      onChoose: onChoose,
    ),
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
