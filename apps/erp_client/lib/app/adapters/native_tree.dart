import 'package:flutter/material.dart';

import '../../core/models/native_models.dart';
import '../../document_editor.dart';
import '../../erp_api.dart';
import '../../features/catalog/data/erp_catalog_repository.dart';
import '../../features/catalog/models/catalog_models.dart';
import '../../features/catalog/presentation/native_tree_view.dart';
import '../../features/catalog/presentation/native_tree_view_model.dart';
import '../gates/access_gate.dart';

class NativeTreeScreen extends StatefulWidget {
  const NativeTreeScreen({
    super.key,
    required this.api,
    required this.type,
    this.company,
    this.parent,
    this.parentTitle,
  });
  final ErpApi api;
  final NativeType type;
  final String? company, parent, parentTitle;
  @override
  State<NativeTreeScreen> createState() => _NativeTreeScreenState();
}

class _NativeTreeScreenState extends State<NativeTreeScreen> {
  late ErpCatalogRepository _repository;
  late NativeTreeViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.type.name,
    widget.parent,
  );
  void _create() {
    _repository = ErpCatalogRepository(
      api: widget.api,
      company: widget.company,
    );
    _owned = _ownership;
    _access = _repository.scope;
    _model = NativeTreeViewModel(
      _repository,
      type: widget.type,
      company: widget.company,
      parent: widget.parent,
    );
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
      if (mounted) {
        setState(() {});
      }
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(covariant NativeTreeScreen oldWidget) {
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

  Future<void> _open(String? name) async {
    final api = widget.api,
        type = widget.type,
        company = widget.company,
        parent = widget.parent;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: type.name,
          name: name,
          company: company,
          treeParent: name == null ? parent : null,
        ),
      ),
    );
  }

  Future<void> _browse(NativeTreeNode node) async {
    if (!node.expandable) {
      await _open(node.name);
      return;
    }
    final api = widget.api, type = widget.type, company = widget.company;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NativeTreeScreen(
          api: api,
          type: type,
          company: company,
          parent: node.name,
          parentTitle: node.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => NativeTreeView(
    model: _model,
    parentTitle: widget.parentTitle,
    open: _open,
    browse: _browse,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
