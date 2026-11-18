import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/erp_exception.dart';
import '../../document_editor.dart';
import '../../document_fields.dart';
import '../../erp_api.dart' show ErpApi;
import '../../features/reports/data/erp_report_repository.dart';
import '../../features/reports/presentation/native_report_view.dart';
import '../../features/reports/presentation/report_view_model.dart';
import '../../file_actions.dart';
import '../gates/access_gate.dart';

class NativeReportScreen extends StatefulWidget {
  const NativeReportScreen({
    super.key,
    required this.api,
    required this.name,
    this.company,
  });
  final ErpApi api;
  final String name;
  final String? company;
  @override
  State<NativeReportScreen> createState() => _NativeReportScreenState();
}

class _NativeReportScreenState extends State<NativeReportScreen> {
  late ErpReportRepository _repository;
  late ReportViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.name,
  );
  void _create() {
    _owned = _ownership;
    _repository = ErpReportRepository(
      api: widget.api,
      name: widget.name,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = ReportViewModel(_repository);
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
  void didUpdateWidget(covariant NativeReportScreen oldWidget) {
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

  void _open(String type, String name) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: type,
          name: name,
          company: company,
        ),
      ),
    );
  }

  Future<void> _export(ReportViewModel model, AppliedReport applied) async {
    if (!mounted || !identical(model, _model) || !model.canExport(applied)) {
      throw const ErpException(
        'Workspace access changed. Refresh this workspace.',
        permissionDenied: true,
      );
    }
    final scope = model.scope;
    await saveOrShareFile(
      context,
      '${widget.name}.csv',
      Uint8List.fromList(utf8.encode(model.csv(applied))),
      mime: 'text/csv',
      canContinue: () =>
          mounted &&
          identical(model, _model) &&
          model.isCurrent(scope) &&
          model.canExport(applied),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return NativeReportView(
      model: model,
      name: widget.name,
      filterFields: (schema, values, errors, changed) => DocumentFields(
        schema: schema,
        data: values,
        errors: errors,
        onChanged: changed,
        onLink: model.links,
        scopeKey: model.scope,
      ),
      open: _open,
      exportFile: (applied) => _export(model, applied),
      protect: (child, reload) => AccessGate(
        key: ValueKey(_owned),
        api: widget.api,
        revalidate: reload,
        child: child,
      ),
    );
  }
}
