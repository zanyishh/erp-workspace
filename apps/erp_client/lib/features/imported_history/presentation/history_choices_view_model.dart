import 'package:flutter/foundation.dart';

import '../../../core/models/json_values.dart';
import '../data/history_repository.dart';

class HistoryChoicesViewModel extends ChangeNotifier {
  HistoryChoicesViewModel(
    this._repository, {
    required this.family,
    required this.field,
    required Map<String, dynamic> filters,
  }) : _owner = _repository.identity,
       _openedScope = _repository.scope,
       _filters = immutableJsonMap(copyJsonMap(filters)) {
    reload();
  }
  final ImportedHistoryRepository _repository;
  final Object _owner;
  final Object? _openedScope;
  final String family, field;
  final Map<String, dynamic> _filters;
  bool _disposed = false, _loading = true, _more = false;
  int _generation = 0, _start = 0;
  String _query = '';
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  late Future<void> _settled;
  Future<void> get settled => _settled;
  bool get valid =>
      !_disposed &&
      _owner == _repository.identity &&
      _openedScope != null &&
      _openedScope == _repository.scope;
  List<Map<String, dynamic>> get rows => valid ? _rows : const [];
  bool get loading => valid && _loading;
  bool get hasMore => valid && _more;
  String? get error => valid
      ? _error
      : (!_disposed
            ? 'Your history access changed. Reopen the filters.'
            : null);
  int get start => _start;
  String get query => _query;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    _generation++;
    _rows = [];
    _more = false;
    _loading = false;
    _error = 'Your history access changed. Reopen the filters.';
    _notify();
  }

  Future<void> reload() => _settled = _load();
  Future<void> _load() async {
    if (!valid) {
      invalidate();
      return;
    }
    final generation = ++_generation, offset = _start, query = _query;
    _loading = true;
    _rows = [];
    _error = null;
    _more = false;
    _notify();
    try {
      final page = await _repository.options(
        family,
        field,
        query: query,
        start: offset,
        filters: _filters,
      );
      if (!valid || generation != _generation) return;
      _rows = page.rows;
      _more = page.hasMore;
      _loading = false;
      _notify();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _error = error.toString();
        _loading = false;
        _notify();
      }
    }
  }

  void beginSearch() {
    if (!valid) return;
    _generation++;
    _rows = [];
    _loading = true;
    _more = false;
    _notify();
  }

  Future<void> search(String value) async {
    if (!valid) return;
    _query = value.trim();
    _start = 0;
    await reload();
  }

  Future<void> nextPage() async {
    if (!valid || _loading || !_more) return;
    _start += 50;
    await reload();
  }

  Future<void> previousPage() async {
    if (!valid || _loading || _start == 0) return;
    _start = (_start - 50).clamp(0, _start);
    await reload();
  }

  bool canChoose(Map<String, dynamic> row) =>
      valid && !_loading && _rows.contains(row);
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _rows = [];
    super.dispose();
  }
}
