import 'package:flutter/material.dart';

import '../../document_editor.dart';
import '../../erp_api.dart';
import '../../features/operations/data/erp_operation_repository.dart';
import '../../features/operations/models/operation_reference.dart';
import '../../features/operations/presentation/pending_operations_view.dart';
import '../../features/operations/presentation/pending_operations_view_model.dart';
import '../../ui/access_gate.dart';

/// Composes recovery reads and explicit ledger actions; never replays a business write.
class PendingOperationsScreen extends StatefulWidget {
  const PendingOperationsScreen({
    super.key,
    required this.api,
    required this.company,
  });
  final ErpApi api;
  final String company;
  @override
  State<PendingOperationsScreen> createState() => _PendingOperationsState();
}

class _PendingOperationsState extends State<PendingOperationsScreen> {
  late PendingOperationsViewModel _model = _createModel();
  PendingOperationsViewModel _createModel() => PendingOperationsViewModel(
    ErpOperationRepository(api: widget.api, company: widget.company),
  );
  @override
  void didUpdateWidget(covariant PendingOperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.company != widget.company) {
      _model.dispose();
      _model = _createModel();
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _open(OperationTarget target) async {
    final api = widget.api, company = widget.company;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          company: company,
          doctype: target.doctype,
          name: target.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PendingOperationsView(
    model: _model,
    company: widget.company,
    open: _open,
    protect: (child, reload) => AccessGate(
      key: ValueKey(widget.company),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
