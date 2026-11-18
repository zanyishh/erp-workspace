import 'package:flutter/material.dart';

import '../../document_editor.dart';
import '../../erp_api.dart' show ErpApi;
import 'history_filters.dart';
import 'imported_record_preview.dart';
import 'invoice_preview.dart';
import '../../features/imported_history/data/erp_history_repository.dart';
import '../../features/imported_history/models/history_filter_intent.dart';
import '../../features/imported_history/presentation/history_register_view_model.dart';
import '../../features/imported_history/presentation/history_detail_view_model.dart';
import '../../features/imported_history/presentation/original_production_view_model.dart';
import '../../features/imported_history/presentation/imported_history_view.dart';
import '../../features/imported_history/presentation/imported_history_detail_view.dart';
import '../../features/imported_history/presentation/original_production_view.dart';
import '../gates/access_gate.dart';

class ImportedHistoryScreen extends StatefulWidget {
  const ImportedHistoryScreen({
    super.key,
    required this.api,
    required this.company,
    this.initialFamily,
    this.initialFilters = const {},
  });
  final ErpApi api;
  final String company;
  final String? initialFamily;
  final Map<String, dynamic> initialFilters;
  @override
  State<ImportedHistoryScreen> createState() => _ImportedHistoryScreenState();
}

class ImportedHistoryDetailScreen extends StatefulWidget {
  const ImportedHistoryDetailScreen({
    super.key,
    required this.api,
    required this.company,
    required this.name,
  });
  final ErpApi api;
  final String company, name;
  @override
  State<ImportedHistoryDetailScreen> createState() =>
      _ImportedHistoryDetailScreenState();
}

/// Read-only sums of preserved original records; these are not native events.
class OriginalProductionReport extends StatefulWidget {
  const OriginalProductionReport({
    super.key,
    required this.api,
    required this.company,
    this.initialFilters = const {},
  });
  final ErpApi api;
  final String company;
  final Map<String, dynamic> initialFilters;
  @override
  State<OriginalProductionReport> createState() =>
      _OriginalProductionReportState();
}

class _ImportedHistoryScreenState extends State<ImportedHistoryScreen> {
  late ErpImportedHistoryRepository _repository;
  late HistoryRegisterViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership =>
      (widget.api, widget.api.baseUri, widget.api.account, widget.company);
  void _create() {
    _owned = _ownership;
    _repository = ErpImportedHistoryRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = HistoryRegisterViewModel(
      _repository,
      initialFamily: widget.initialFamily,
      initialFilters: widget.initialFilters,
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
  void didUpdateWidget(covariant ImportedHistoryScreen oldWidget) {
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

  Future<Map<String, dynamic>?> _filters(HistoryFilterIntent intent) {
    final api = widget.api, company = widget.company;
    return editHistoryFilters(
      context,
      api,
      company,
      intent.family,
      intent.fields,
      intent.filters,
      labels: intent.labels,
    );
  }

  void _open(String name) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImportedHistoryDetailScreen(api: api, company: company, name: name),
      ),
    );
  }

  void _production(Map<String, dynamic> filters) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OriginalProductionReport(
          api: api,
          company: company,
          initialFilters: Map.from(filters),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ImportedHistoryView(
    model: _model,
    company: widget.company,
    editFilters: _filters,
    openRecord: _open,
    openProduction: _production,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}

class _ImportedHistoryDetailScreenState
    extends State<ImportedHistoryDetailScreen> {
  late ErpImportedHistoryRepository _repository;
  late HistoryDetailViewModel _model;
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
    _repository = ErpImportedHistoryRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = HistoryDetailViewModel(_repository, name: widget.name);
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
  void didUpdateWidget(covariant ImportedHistoryDetailScreen oldWidget) {
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

  void _target(String type, String name) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditor(
          api: api,
          company: company,
          doctype: type,
          name: name,
        ),
      ),
    );
  }

  void _record() {
    final api = widget.api, company = widget.company, name = widget.name;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImportedRecordPreviewScreen(api: api, company: company, name: name),
      ),
    );
  }

  void _invoice(String reference) {
    final api = widget.api, company = widget.company, name = widget.name;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(
          api: api,
          company: company,
          invoice: reference,
          importedRecord: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ImportedHistoryDetailView(
    model: _model,
    openTarget: _target,
    openRecord: _record,
    openInvoice: _invoice,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}

class _OriginalProductionReportState extends State<OriginalProductionReport> {
  late ErpImportedHistoryRepository _repository;
  late OriginalProductionViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership =>
      (widget.api, widget.api.baseUri, widget.api.account, widget.company);
  void _create() {
    _owned = _ownership;
    _repository = ErpImportedHistoryRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = OriginalProductionViewModel(
      _repository,
      initialFilters: widget.initialFilters,
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
  void didUpdateWidget(covariant OriginalProductionReport oldWidget) {
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

  Future<Map<String, dynamic>?> _filters(HistoryFilterIntent intent) {
    final api = widget.api, company = widget.company;
    return editHistoryFilters(
      context,
      api,
      company,
      intent.family,
      intent.fields,
      intent.filters,
      labels: intent.labels,
    );
  }

  void _history(Map<String, dynamic> filters) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportedHistoryScreen(
          api: api,
          company: company,
          initialFamily: 'production',
          initialFilters: filters,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OriginalProductionView(
    model: _model,
    company: widget.company,
    editFilters: _filters,
    openHistory: _history,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
