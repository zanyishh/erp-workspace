import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import '../data/history_repository.dart';
import '../models/history_filter_intent.dart';

class HistoryRegisterViewModel extends ChangeNotifier {
  HistoryRegisterViewModel(
    this._repository, {
    String? initialFamily,
    Map<String, dynamic> initialFilters = const {},
  }) : _owner = _repository.identity,
       _family = initialFamily,
       _filters = immutableJsonMap(copyJsonMap(initialFilters)) {
    loadSummary();
  }
  final ImportedHistoryRepository _repository;
  final Object _owner;
  bool _disposed = false, _loading = true, _shared = false, _hasMore = false;
  int _generation = 0, _start = 0;
  int? _rowCount;
  Object? _stateScope;
  String? _family, _error;
  String _query = '';
  Map<String, dynamic> _filters;
  List<Map<String, dynamic>> _families = [], _rows = [], _cash = [];
  List<String> _filterFields = [];
  Map<String, String> _filterLabels = {};
  late Future<void> _settled;
  Future<void> get settled => _settled;
  Object get scope => (_owner, _repository.scope);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && value == scope;
  bool get _current => isCurrent(_stateScope ?? Object());
  List<Map<String, dynamic>> get families => _current ? _families : const [];
  List<Map<String, dynamic>> get rows => _current ? _rows : const [];
  List<Map<String, dynamic>> get cashBalances => _current ? _cash : const [];
  List<String> get filterFields => _current ? _filterFields : const [];
  Map<String, String> get filterLabels => _current ? _filterLabels : const {};
  Map<String, dynamic> get filters => _current ? _filters : const {};
  String? get family => _current ? _family : null;
  String get query => _current ? _query : '';
  int get start => _current ? _start : 0;
  int? get rowCount => _current ? _rowCount : null;
  bool get loading => _current && _loading;
  bool get sharedAvailable => _current && _shared;
  bool get canReadProduction => _active && _repository.canReadProduction;
  bool get hasMore => _current && _hasMore;
  String? get error => _current ? _error : null;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _accept(int generation, Object scope) =>
      isCurrent(scope) && generation == _generation;
  void _clearRows() {
    _rows = [];
    _cash = [];
    _filterLabels = {};
    _hasMore = false;
    _rowCount = null;
  }

  Future<void> loadSummary() => _settled = _summary();
  Future<void> _summary() async {
    final request = ++_generation, captured = scope;
    if (_stateScope != captured) {
      _families = [];
      _shared = false;
    }
    _stateScope = captured;
    _clearRows();
    _start = 0;
    _loading = true;
    _error = null;
    _notify();
    try {
      if (!_active) throw _changed;
      final data = await _repository.summary();
      if (!_accept(request, captured)) return;
      _families = data.families;
      _shared = data.sharedAvailable;
      final keys = _families.map((row) => row['key']?.toString() ?? '').toSet();
      if (!keys.contains(_family) && !(_family == 'shared_cash' && _shared)) {
        _family = _families.isEmpty
            ? (_shared ? 'shared_cash' : null)
            : _families.first['key'].toString();
      }
      _loading = false;
      _notify();
      if (_family != null) await reload();
    } catch (error) {
      if (_accept(request, captured)) {
        _error = error.toString();
        _loading = false;
        _families = [];
        _shared = false;
        _notify();
      }
    }
  }

  Future<void> reload({bool reset = false}) {
    if (reset) _start = 0;
    return _settled = _page();
  }

  Future<void> _page() async {
    final selected = _family;
    if (selected == null) return;
    final request = ++_generation, captured = scope, offset = _start;
    final filters = immutableJsonMap(_filters), query = _query;
    _stateScope = captured;
    _clearRows();
    _error = null;
    _loading = true;
    _notify();
    try {
      if (!_active) throw _changed;
      final page = await _repository.records(
        selected,
        query: query,
        start: offset,
        pageLength: 40,
        filters: filters,
      );
      if (!_accept(request, captured)) return;
      _rows = page.rows;
      _cash = page.cashBalances;
      _filterLabels = page.filterLabels;
      _filterFields = page.filterFields;
      _hasMore = page.hasMore;
      _rowCount = page.rowCount;
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

  Future<void> chooseFamily(String? value) async {
    if (!_current ||
        value == null ||
        value == _family ||
        !(_families.any((row) => row['key']?.toString() == value) ||
            value == 'shared_cash' && _shared)) {
      return;
    }
    _family = value;
    _start = 0;
    _query = '';
    _filters = {};
    _filterFields = [];
    await reload();
  }

  void beginSearch() {
    if (!_current) return;
    _generation++;
    _rows = [];
    _hasMore = false;
    _loading = true;
    _notify();
  }

  Future<void> search(String value) async {
    if (!_current) return;
    _query = value.trim();
    _start = 0;
    await reload();
  }

  Future<void> clearFilters() async {
    if (!_current) return;
    _filters = {};
    _start = 0;
    await reload();
  }

  Future<void> nextPage() async {
    if (!_current || _loading || !_hasMore) return;
    _start += 40;
    await reload();
  }

  Future<void> previousPage() async {
    if (!_current || _loading || _start == 0) return;
    _start = (_start - 40).clamp(0, _start);
    await reload();
  }

  HistoryFilterIntent? prepareFilters() {
    final selected = _family;
    if (!_current || selected == null) return null;
    return HistoryFilterIntent(
      owner: this,
      scope: scope,
      generation: _generation,
      family: selected,
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
        !intent.belongsTo(this, scope, _generation, _family ?? '')) {
      return false;
    }
    _filters = immutableJsonMap(copyJsonMap(values));
    _start = 0;
    await reload();
    return true;
  }

  bool canOpen(String name) =>
      _current && _rows.any((row) => row['name'] == name);
  Future<void> revalidate() async {
    if (!_active) throw _changed;
    _filters = {};
    _filterFields = [];
    _query = '';
    await loadSummary();
    if (error != null) throw ErpException(error!);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _clearRows();
    _families = [];
    _filters = {};
    _filterFields = [];
    super.dispose();
  }
}
