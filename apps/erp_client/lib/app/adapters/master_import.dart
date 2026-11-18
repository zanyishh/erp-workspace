import 'package:flutter/material.dart';

import '../../erp_api.dart';
import '../../file_actions.dart';
import '../../features/catalog/data/erp_catalog_repository.dart';
import '../../features/catalog/data/master_import_file_service.dart';
import '../../features/catalog/presentation/master_import_view.dart';
import '../../features/catalog/presentation/master_import_view_model.dart';
import '../gates/access_gate.dart';

class MasterImportScreen extends StatefulWidget {
  const MasterImportScreen({
    super.key,
    required this.api,
    required this.doctype,
    required this.company,
  });
  final ErpApi api;
  final String doctype, company;
  @override
  State<MasterImportScreen> createState() => _MasterImportScreenState();
}

class _MasterImportScreenState extends State<MasterImportScreen> {
  late ErpCatalogRepository _repository;
  late MasterImportViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.doctype,
  );
  void _create() {
    _repository = ErpCatalogRepository(
      api: widget.api,
      company: widget.company,
    );
    _owned = _ownership;
    _access = _repository.scope;
    final files = MasterImportFileService();
    late final MasterImportViewModel model;
    model = MasterImportViewModel(
      _repository,
      doctype: widget.doctype,
      company: widget.company,
      chooseFile: () => files.choose(selected: model.selectedFilename),
      saveFile: (name, bytes) async {
        if (mounted) {
          await saveOrShareFile(context, name, bytes, mime: 'text/csv');
        }
      },
    );
    _model = model;
  }

  @override
  void initState() {
    super.initState();
    _create();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) {
      return;
    }
    if (_owned != _ownership) {
      _model.dispose();
      _create();
      setState(() {});
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      _model.invalidate();
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MasterImportScreen oldWidget) {
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
  Widget build(BuildContext context) => MasterImportView(
    model: _model,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
