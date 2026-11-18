import 'package:flutter/material.dart';

import '../../erp_api.dart' show ErpApi;
import '../../features/imported_history/data/erp_history_repository.dart';
import '../../features/imported_history/presentation/history_filters_view.dart';
import '../../features/imported_history/presentation/history_filters_view_model.dart';
import '../../features/imported_history/presentation/history_choices_view.dart';
import '../../features/imported_history/presentation/history_choices_view_model.dart';

Future<Map<String, dynamic>?> editHistoryFilters(
  BuildContext context,
  ErpApi api,
  String company,
  String family,
  List<String> fields,
  Map<String, dynamic> initial, {
  Map<String, String> labels = const {},
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _HistoryFiltersAdapter(
    api: api,
    company: company,
    family: family,
    fields: fields,
    initial: initial,
    labels: labels,
  ),
);

class _HistoryFiltersAdapter extends StatefulWidget {
  const _HistoryFiltersAdapter({
    required this.api,
    required this.company,
    required this.family,
    required this.fields,
    required this.initial,
    required this.labels,
  });
  final ErpApi api;
  final String company, family;
  final List<String> fields;
  final Map<String, dynamic> initial;
  final Map<String, String> labels;
  @override
  State<_HistoryFiltersAdapter> createState() => _HistoryFiltersAdapterState();
}

class _HistoryFiltersAdapterState extends State<_HistoryFiltersAdapter> {
  late final _model = HistoryFiltersViewModel(
    ErpImportedHistoryRepository(api: widget.api, company: widget.company),
    family: widget.family,
    fields: widget.fields,
    initial: widget.initial,
    labels: widget.labels,
  );
  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (mounted && !_model.valid) {
      _model.invalidate();
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    _model.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _choose(HistoryChoiceIntent intent) {
    final api = widget.api, company = widget.company;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _HistoryChoicesAdapter(
        api: api,
        company: company,
        family: intent.family,
        field: intent.field,
        filters: intent.filters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      HistoryFiltersView(model: _model, choose: _choose);
}

class _HistoryChoicesAdapter extends StatefulWidget {
  const _HistoryChoicesAdapter({
    required this.api,
    required this.company,
    required this.family,
    required this.field,
    required this.filters,
  });
  final ErpApi api;
  final String company, family, field;
  final Map<String, dynamic> filters;
  @override
  State<_HistoryChoicesAdapter> createState() => _HistoryChoicesAdapterState();
}

class _HistoryChoicesAdapterState extends State<_HistoryChoicesAdapter> {
  late final _model = HistoryChoicesViewModel(
    ErpImportedHistoryRepository(api: widget.api, company: widget.company),
    family: widget.family,
    field: widget.field,
    filters: widget.filters,
  );
  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (mounted && !_model.valid) {
      _model.invalidate();
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HistoryChoicesView(model: _model);
}
