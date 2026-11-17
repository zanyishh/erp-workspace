import '../../../core/models/erp_exception.dart';
import '../data/history_repository.dart';
import '../models/history_models.dart';

class HistoryDetailViewModel {
  HistoryDetailViewModel(this._repository, {required this.name})
    : _owner = _repository.identity {
    reload();
  }
  final ImportedHistoryRepository _repository;
  final Object _owner;
  final String name;
  bool _disposed = false;
  int _generation = 0;
  Object? _loadedScope;
  late Future<HistoryDetail> _result;
  Future<HistoryDetail> get result => _result;
  Object get scope => (_owner, _repository.scope, name, _generation);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && scope == value;
  bool get ready => isCurrent(_loadedScope ?? Object());
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Future<HistoryDetail> reload() {
    final generation = ++_generation, captured = scope;
    _loadedScope = null;
    _result = _active ? _read(generation, captured) : Future.error(_changed);
    _result.ignore();
    return _result;
  }

  Future<HistoryDetail> _read(int generation, Object captured) async {
    final value = await _repository.detail(name);
    if (!isCurrent(captured) || generation != _generation) throw _changed;
    _loadedScope = captured;
    return value;
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _loadedScope = null;
  }
}
