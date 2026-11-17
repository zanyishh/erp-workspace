import 'package:flutter/material.dart';

import '../../erp_api.dart' show ErpApi;
import '../../features/invoices/data/erp_invoice_repository.dart';
import '../../features/invoices/data/invoice_logo_service.dart';
import '../../features/invoices/presentation/invoice_settings_view.dart';
import '../../features/invoices/presentation/invoice_settings_view_model.dart';
import '../gates/access_gate.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({
    super.key,
    required this.api,
    required this.company,
  });
  final ErpApi api;
  final String company;
  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsState();
}

class _InvoiceSettingsState extends State<InvoiceSettingsScreen> {
  final _logo = const InvoiceLogoService();
  late ErpInvoiceRepository _repository;
  late InvoiceSettingsViewModel _model;
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
    _model = InvoiceSettingsViewModel(_repository, pickLogo: _logo.pick);
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
  void didUpdateWidget(covariant InvoiceSettingsScreen oldWidget) {
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

  @override
  Widget build(BuildContext context) => InvoiceSettingsView(
    model: _model,
    company: widget.company,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
