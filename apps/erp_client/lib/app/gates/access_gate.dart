import 'package:flutter/material.dart';

import '../../erp_api.dart' show ErpApi;
import '../../features/workspace/data/erp_access_repository.dart';
import '../../features/workspace/presentation/access_gate_view.dart';
import '../../features/workspace/presentation/access_gate_view_model.dart';

/// Composes the access observer without disposing mounted drafts.
class AccessGate extends StatefulWidget {
  const AccessGate({
    super.key,
    required this.api,
    required this.revalidate,
    required this.child,
    this.fullPage = true,
  });
  final ErpApi api;
  final Future<void> Function() revalidate;
  final Widget child;
  final bool fullPage;
  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  late AccessGateViewModel _model = _createModel();
  AccessGateViewModel _createModel({bool validateInitially = false}) =>
      AccessGateViewModel(
        ErpAccessRepository(widget.api),
        revalidate: widget.revalidate,
        validateInitially: validateInitially,
      );
  @override
  void didUpdateWidget(covariant AccessGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api == widget.api) {
      _model.updateReload(widget.revalidate);
      return;
    }
    _model.dispose();
    _model = _createModel(validateInitially: true);
    final model = _model;
    if (model.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(model, _model)) model.refresh();
      });
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccessGateView(
    model: _model,
    fullPage: widget.fullPage,
    child: widget.child,
  );
}
