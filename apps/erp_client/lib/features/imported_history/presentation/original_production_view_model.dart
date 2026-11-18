import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import '../data/history_repository.dart';
import '../models/history_filter_intent.dart';

const originalProductionGroups = {
  'original_date': 'Date',
  'machine': 'Machine',
  'operator': 'Employee / operator',
  'shift': 'Shift',
  'party': 'Customer',
  'description': 'Fabric',
  'dia': 'Dia / size',
};

class OriginalProductionViewModel extends ChangeNotifier {
  OriginalProductionViewModel(
    this._repository, {
    Map<String, dynamic> initialFilters = const {},
  }) : _owner = _repository.identity,
       _filters = immutableJsonMap(copyJsonMap(initialFilters)) {
    reload();
  }
  final ImportedHistoryRepository _repository;
  final Object _owner;
  bool _disposed = false, _loading = true, _hasMore = false;
  int _generation = 0, _start = 0, _rowCount = 0;
  Object? _stateScope;
  String _group = 'original_date';
  String? _error;
  Map<String, dynamic> _filters;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _totals;
  List<String> _filterFields = [];
  Map<String, String> _filterLabels = {};
  late Future<void> _settled;
  Future<void> get settled => _settled;
  Object get scope => (_owner, _repository.scope);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && value == scope;
  bool get _current => isCurrent(_stateScope ?? Object());
  bool get allowed => _active && _repository.canReadProduction;
  String get group => _group;
  Map<String, dynamic> get filters => _current ? _filters : const {};
  List<Map<String, dynamic>> get rows => _current && allowed ? _rows : const [];
  Map<String, dynamic>? get totals => _current && allowed ? _totals : null;
  List<String> get filterFields => _current ? _filterFields : const [];
  Map<String, String> get filterLabels => _current ? _filterLabels : const {};
  String? get error => _current ? _error : null;
  int get start => _current ? _start : 0;
  int get rowCount => _current ? _rowCount : 0;
  bool get loading => _current && _loading;
  bool get hasMore => _current && allowed && _hasMore;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _accept(int generation, Object scope) =>
      isCurrent(scope) && generation == _generation;
  static const _changed = ErpException(
    'Your access to original production changed.',
  );
  Future<void> reload() => _settled = _load();
  Future<void> _load() async {
    final request = ++_generation,
        captured = scope,
        selected = _group,
        offset = _start;
    final filters = immutableJsonMap(_filters);
    _stateScope = captured;
    _rows = [];
    _totals = null;
    _filterLabels = {};
    _hasMore = false;
    _rowCount = 0;
    _filterFields = [];
    _loading = true;
    _error = null;
    _notify();
    try {
      if (!allowed) throw _changed;
      final page = await _repository.production(
        groupBy: selected,
        filters: filters,
        start: offset,
        pageLength: 100,
      );
      if (!_accept(request, captured) || !allowed) return;
      _rows = page.rows;
      _totals = page.totals;
      _filterFields = page.filterFields;
      _filterLabels = page.filterLabels;
      _rowCount = page.rowCount;
      _hasMore = page.hasMore;
      _loading = false;
      _notify();
    } catch (error) {
      if (_accept(request, captured)) {
        _error = error.toString();
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> chooseGroup(String? value) async {
    if (!_current ||
        value == null ||
        !originalProductionGroups.containsKey(value) ||
        value == _group) {
      return;
    }
    _group = value;
    _start = 0;
    await reload();
  }

  Future<void> nextPage() async {
    if (!_current || !allowed || _loading || !_hasMore) return;
    _start += 100;
    await reload();
  }

  Future<void> clearFilters() async {
    if (!_current || !allowed) return;
    _filters = {};
    _start = 0;
    await reload();
  }

  Future<void> previousPage() async {
    if (!_current || !allowed || _loading || _start == 0) return;
    _start = (_start - 100).clamp(0, _start);
    await reload();
  }

  HistoryFilterIntent? prepareFilters() {
    if (!_current || !allowed) return null;
    return HistoryFilterIntent(
      owner: this,
      scope: scope,
      generation: _generation,
      family: 'production',
      fields: _filterFields,
      filters: _filters,
      labels: _filterLabels,
    );
  }

  Future<bool> applyFilters(
    HistoryFilterIntent intent,
    Map<String, dynamic> values,
  ) async {
    if (!_current ||
        !allowed ||
        !intent.belongsTo(this, scope, _generation, 'production')) {
      return false;
    }
    _filters = immutableJsonMap(copyJsonMap(values));
    _start = 0;
    await reload();
    return true;
  }

  bool canDrill(Map<String, dynamic> row) =>
      _current && allowed && row['drillable'] == true && _rows.contains(row);
  Future<void> revalidate() async {
    _generation++;
    _rows = [];
    _totals = null;
    _filterLabels = {};
    _loading = false;
    _notify();
    if (!allowed) throw _changed;
    _start = 0;
    await reload();
    if (error != null) throw ErpException(error!);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _rows = [];
    _totals = null;
    _filters = {};
    super.dispose();
  }
}
