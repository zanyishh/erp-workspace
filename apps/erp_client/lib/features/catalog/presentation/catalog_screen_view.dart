import 'package:flutter/material.dart';

import '../../../core/models/native_models.dart';
import '../../../core/ui/widgets.dart';
import '../models/catalog_models.dart';
import 'catalog_browse_view.dart';
import 'catalog_browse_view_model.dart';
import 'catalog_view_model.dart';

class CatalogScreenView extends StatefulWidget {
  const CatalogScreenView({
    super.key,
    required this.model,
    required this.onType,
    required this.protect,
    this.onReport,
    this.onReconcile,
    this.onBankMatch,
    this.create = false,
    this.knittingOnly = false,
  });
  final CatalogViewModel model;
  final ValueChanged<NativeType> onType;
  final ValueChanged<String>? onReport;
  final VoidCallback? onReconcile, onBankMatch;
  final bool create, knittingOnly;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<CatalogScreenView> createState() => _CatalogScreenViewState();
}

class _CatalogScreenViewState extends State<CatalogScreenView> {
  CatalogBrowseViewModel? _browse;
  Object? _browseScope;
  @override
  void didUpdateWidget(covariant CatalogScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _browse = null;
      _browseScope = null;
    }
  }

  Future<void> _reload() async {
    final future = widget.model.reload();
    setState(() {});
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model, scope = widget.model.scope;
    return widget.protect(
      Scaffold(
        appBar: AppBar(
          title: Text(
            widget.create
                ? 'New document'
                : widget.knittingOnly
                ? 'Company records'
                : 'All modules & settings',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (widget.onReconcile != null || widget.onBankMatch != null)
              PopupMenuButton<String>(
                tooltip: 'Account actions',
                icon: const Icon(Icons.account_balance_outlined),
                onSelected: (action) => action == 'reconcile'
                    ? widget.onReconcile?.call()
                    : widget.onBankMatch?.call(),
                itemBuilder: (_) => [
                  if (widget.onReconcile != null)
                    const PopupMenuItem(
                      value: 'reconcile',
                      child: Text('Reconcile payments'),
                    ),
                  if (widget.onBankMatch != null)
                    const PopupMenuItem(
                      value: 'bank',
                      child: Text('Match bank statement'),
                    ),
                ],
              ),
          ],
        ),
        body: WorkspaceBackdrop(
          child: FutureBuilder<CatalogSnapshot>(
            key: ValueKey(scope),
            future: model.result,
            builder: (context, state) {
              final data = state.data;
              if (data != null) {
                if (_browse == null || _browseScope != scope) {
                  _browse = CatalogBrowseViewModel(
                    data,
                    create: widget.create,
                    allowReports: widget.onReport != null,
                    knittingOnly: widget.knittingOnly,
                  );
                  _browseScope = scope;
                } else {
                  _browse!.updateCatalog(data);
                  _browse!.configure(
                    create: widget.create,
                    allowReports: widget.onReport != null,
                    knittingOnly: widget.knittingOnly,
                  );
                }
                return CatalogBrowseView(
                  key: ValueKey(scope),
                  model: _browse!,
                  onType: (type) {
                    if (model == widget.model && model.isCurrent(scope)) {
                      widget.onType(type);
                    }
                  },
                  onReport: widget.onReport == null
                      ? null
                      : (name) {
                          if (model == widget.model && model.isCurrent(scope)) {
                            widget.onReport!(name);
                          }
                        },
                );
              }
              // The original grid loses its local search state when replaced by an
              // error or an initial load; keep model and controller lifetimes aligned.
              _browse = null;
              _browseScope = null;
              if (state.hasError) {
                return MessagePanel(
                  title: 'COULD NOT LOAD MODULES',
                  message: state.error.toString(),
                  action: () => _reload(),
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
      _reload,
    );
  }
}
