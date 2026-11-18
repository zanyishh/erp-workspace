import 'package:flutter/material.dart';

import '../../core/models/erp_models.dart';
import '../../features/overview/data/module_record_repository.dart';
import '../../features/overview/presentation/module_browser_view.dart';
import '../../features/overview/presentation/module_browser_view_model.dart';
export '../../features/overview/data/module_record_repository.dart'
    show RecordLoader;

class ModuleBrowser extends StatefulWidget {
  const ModuleBrowser({
    super.key,
    required this.module,
    required this.company,
    required this.currency,
    required this.loader,
    required this.onRecord,
    required this.onCreate,
    required this.onBrowseAll,
    this.onShowAll,
    this.onReconcile,
    this.onBankMatch,
    this.onCheckout,
    this.onInvoices,
    this.onImportedHistory,
    this.refreshRevision = 0,
    this.showCompany = true,
    this.scope,
  });
  final int refreshRevision;
  final bool showCompany;
  final Object? scope;
  final VoidCallback? onInvoices;
  final VoidCallback? onImportedHistory;
  final ErpModule module;
  final String company, currency;
  final RecordLoader loader;
  final ValueChanged<ErpRecord> onRecord;
  final VoidCallback? onCreate;
  final VoidCallback onBrowseAll;
  final VoidCallback? onShowAll;
  final VoidCallback? onReconcile, onBankMatch, onCheckout;
  @override
  State<ModuleBrowser> createState() => _ModuleBrowserState();
}

class _ModuleBrowserState extends State<ModuleBrowser> {
  late ModuleBrowserViewModel _model = _createModel();
  ModuleBrowserViewModel _createModel() => ModuleBrowserViewModel(
    CallbackModuleRecordRepository(
      (query, start) => widget.loader(query, start),
    ),
    company: widget.company,
    currency: widget.currency,
    module: widget.module,
    scope: widget.scope,
  );
  @override
  void didUpdateWidget(covariant ModuleBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.company != widget.company ||
        oldWidget.module != widget.module) {
      _model.dispose();
      _model = _createModel();
    } else {
      _model.updateCurrency(widget.currency);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModuleBrowserView(
    model: _model,
    refreshRevision: widget.refreshRevision,
    showCompany: widget.showCompany,
    onRecord: widget.onRecord,
    onCreate: widget.onCreate,
    onBrowseAll: widget.onBrowseAll,
    onShowAll: widget.onShowAll,
    onReconcile: widget.onReconcile,
    onBankMatch: widget.onBankMatch,
    onCheckout: widget.onCheckout,
    onInvoices: widget.onInvoices,
    onImportedHistory: widget.onImportedHistory,
  );
}
