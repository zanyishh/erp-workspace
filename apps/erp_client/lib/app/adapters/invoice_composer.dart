import 'package:flutter/material.dart';

import '../../document_editor.dart';
import '../../document_fields.dart';
import '../../erp_api.dart' show ErpApi;
import '../../core/models/native_models.dart';
import '../../features/invoices/data/erp_invoice_repository.dart';
import '../../features/invoices/presentation/invoice_composer_view.dart';
import '../../features/invoices/presentation/invoice_composer_view_model.dart';
import '../gates/access_gate.dart';

class InvoiceComposer extends StatefulWidget {
  const InvoiceComposer({
    super.key,
    required this.api,
    required this.company,
    this.templateId,
    this.continueToEditor = false,
  });
  final ErpApi api;
  final String company;
  final String? templateId;
  final bool continueToEditor;
  @override
  State<InvoiceComposer> createState() => _InvoiceComposerState();
}

class _InvoiceComposerState extends State<InvoiceComposer> {
  late InvoiceComposerViewModel _model;
  late ErpInvoiceRepository _repository;
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
    _model = InvoiceComposerViewModel(
      _repository,
      initialTemplate: widget.templateId,
    );
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
  void didUpdateWidget(covariant InvoiceComposer oldWidget) {
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

  Future<String?> _openEditor({String? name}) async {
    final model = _model,
        captured = _model.scope,
        api = widget.api,
        company = widget.company;
    String? created;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: 'Sales Invoice',
          name: name,
          company: company,
          onCreated: name == null
              ? (doc) {
                  created = doc.data['name'] as String?;
                }
              : null,
        ),
      ),
    );
    return mounted && identical(model, _model) && model.isCurrent(captured)
        ? created
        : null;
  }

  Widget _link(
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
  }) => NativeScalarField(
    field: NativeField.fromJson({
      'fieldname': type.toLowerCase(),
      'label': label,
      'fieldtype': 'Link',
      'options': type,
    }),
    linkType: type,
    value: value,
    editable: editable,
    focusNode: focusNode,
    onCommitted: onCommitted,
    error: error,
    scopeKey: scope,
    onChanged: (value) => change(value?.toString() ?? ''),
    onLink: (target, query, _) => search(target, query),
  );
  @override
  Widget build(BuildContext context) => InvoiceComposerView(
    key: ValueKey(_owned),
    model: _model,
    linkField: _link,
    openEditor: _openEditor,
    continueToEditor: widget.continueToEditor,
    protect: (child, revalidate) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: revalidate,
      child: child,
    ),
  );
}
