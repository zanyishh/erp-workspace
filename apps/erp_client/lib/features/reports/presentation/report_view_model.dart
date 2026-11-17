import 'dart:convert';

import '../../../core/models/erp_exception.dart';
import '../../../core/models/native_models.dart';
import '../data/report_repository.dart';
import '../models/native_reports.dart';
import '../models/report_definition.dart';
import '../models/report_values.dart';

class AppliedReport {
  AppliedReport._(
    this._model,
    this._scope,
    this.report,
    this.filters, {
    this.preparedFilters,
  });
  final Object _model, _scope;
  final NativeReportResult report;
  final Map<String, dynamic> filters;
  final Map<String, dynamic>? preparedFilters;
}

class ReportViewModel {
  ReportViewModel(this._repository) : _owner = _repository.identity {
    reloadDefinition();
  }
  final ReportRepository _repository;
  final Object _owner;
  int _definitionVersion = 0, _generation = 0;
  bool _disposed = false;
  Object? _loadedScope, _queueToken;
  ReportDefinition? _definitionData;
  Map<String, dynamic>? _values;
  Map<String, String> _errors = const {};
  Map<String, Object?> _parents = {};
  String? _problem, _queuedKey;
  String _filterKey = '';
  AppliedReport? _lastCompleted;
  late Future<ReportDefinition> _definition;
  Future<AppliedReport>? _result;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Object get scope => (_owner, _repository.scope, _definitionVersion);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object captured) => _active && captured == scope;
  bool get _ready => _active && _loadedScope == scope;
  Future<ReportDefinition> get definition => _definition;
  ReportDefinition? get loadedDefinition => _ready ? _definitionData : null;
  Map<String, dynamic>? get values => _ready ? _values : null;
  Map<String, String> get errors => _ready ? _errors : const {};
  String? get problem => _ready ? _problem : null;
  Future<AppliedReport>? get result => _ready ? _result : null;
  bool get busy => !_disposed && _queueToken != null;
  bool get queued => _ready && _queuedKey == _filterKey;

  Future<ReportDefinition> reloadDefinition() {
    _definitionVersion++;
    _generation++;
    _loadedScope = null;
    _values = null;
    _definitionData = null;
    _result = null;
    _lastCompleted = null;
    _queuedKey = null;
    _errors = const {};
    _parents = {};
    _problem = null;
    _filterKey = '';
    _definition = _active ? _loadDefinition(scope) : Future.error(_changed);
    _definition.ignore();
    return _definition;
  }

  Future<ReportDefinition> _loadDefinition(Object captured) async {
    final definition = await _repository.definition();
    if (!isCurrent(captured)) throw _changed;
    _definitionData = definition;
    _values = copyReportMap(definition.defaults);
    _loadedScope = captured;
    _rememberParents();
    return definition;
  }

  Future<void> revalidate() async => await reloadDefinition();

  void _rememberParents() {
    final fields = _definitionData!.schema.fields;
    _parents = {
      for (final field in fields)
        if (field.multiple &&
            fields.any((parent) => parent.name == field.options))
          field.name: _values![field.options],
    };
  }

  void changed() {
    if (!_ready) return;
    for (final field in _definitionData!.schema.fields.where(
      (f) => f.multiple,
    )) {
      if (_parents.containsKey(field.name) &&
          _parents[field.name] != _values![field.options]) {
        _values![field.name] = <String>[];
      }
    }
    _rememberParents();
    _errors = const {};
    _problem = null;
  }

  Map<String, dynamic> _filters() {
    final definition = _definitionData!, schema = definition.schema;
    final visible = schema.visibleFields(_values!).toSet();
    final filters = <String, dynamic>{};
    for (final field in schema.fields.where((f) => !f.layout)) {
      final value = visible.contains(field)
          ? _values![field.name]
          : definition.defaults[field.name];
      if (value != null && value != '') {
        filters[field.name] = field.parse(value);
      }
    }
    return filters;
  }

  bool filtersChanged(Map<String, dynamic> applied) {
    if (!_ready) return false;
    try {
      return jsonEncode(_filters()) != jsonEncode(applied);
    } on FormatException {
      return true;
    }
  }

  void run() {
    if (!_ready) return;
    final invalid = _definitionData!.schema.validate(_values!);
    if (invalid.isNotEmpty) {
      _errors = Map.unmodifiable(invalid);
      return;
    }
    runFilters(_filters());
  }

  void runFilters(Map<String, dynamic> values) {
    if (!_ready) return;
    final filters = immutableReportMap(copyReportMap(values));
    final key = jsonEncode(filters);
    if (key != _filterKey) _queuedKey = null;
    _filterKey = key;
    final generation = ++_generation, captured = scope;
    _errors = const {};
    _problem = null;
    _result = _run(generation, captured, filters);
    _result!.ignore();
  }

  Future<AppliedReport> _run(
    int generation,
    Object captured,
    Map<String, dynamic> filters,
  ) async {
    try {
      final report = await _repository.run(filters);
      final result = AppliedReport._(this, captured, report, filters);
      if (!isCurrent(captured) || generation != _generation) return result;
      if (report.pending && _lastCompleted != null) {
        return AppliedReport._(
          this,
          captured,
          _lastCompleted!.report,
          _lastCompleted!.filters,
          preparedFilters: filters,
        );
      }
      if (!report.pending) _lastCompleted = result;
      return result;
    } catch (error) {
      if (isCurrent(captured) &&
          generation == _generation &&
          error is ErpException &&
          (error.permissionDenied || error.sessionExpired)) {
        _lastCompleted = null;
      }
      rethrow;
    }
  }

  Future<void> queue(Map<String, dynamic> values) async {
    if (!_ready || busy || queued) return;
    final filters = immutableReportMap(copyReportMap(values));
    final key = jsonEncode(filters);
    if (key != _filterKey) return;
    final token = Object(), captured = scope;
    _queueToken = token;
    try {
      await _repository.queue(filters);
      if (isCurrent(captured) && key == _filterKey) {
        _queuedKey = key;
        runFilters(filters);
      }
    } catch (error) {
      if (isCurrent(captured) && key == _filterKey) _problem = error.toString();
    } finally {
      if (identical(_queueToken, token)) _queueToken = null;
    }
  }

  Future<List<Map<String, dynamic>>> links(
    String type,
    String query,
    NativeField field,
  ) async {
    if (!_ready) throw _changed;
    final captured = scope;
    if (field.multiple && field.options.contains('\n')) {
      return List.unmodifiable([
        for (final choice in field.options.split('\n'))
          if (choice.isNotEmpty &&
              choice.toLowerCase().contains(query.toLowerCase()))
            Map<String, dynamic>.unmodifiable({'value': choice}),
      ]);
    }
    final result = await _repository.links(
      type,
      query,
      reference: _definitionData!.reference,
      field: field.name,
    );
    if (!isCurrent(captured)) throw _changed;
    return result;
  }

  bool canUse(AppliedReport applied) =>
      _ready &&
      identical(applied._model, this) &&
      isCurrent(applied._scope) &&
      identical(applied.report, _lastCompleted?.report) &&
      jsonEncode(applied.filters) == jsonEncode(_lastCompleted?.filters);
  bool canExport(AppliedReport applied) =>
      canUse(applied) &&
      _definitionData!.canExport &&
      applied.report.columns.isNotEmpty &&
      applied.report.rows.isNotEmpty;
  String csv(AppliedReport applied) {
    if (!canExport(applied)) throw _changed;
    return applied.report.csv();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _values = null;
    _definitionData = null;
    _result = null;
    _lastCompleted = null;
  }
}
