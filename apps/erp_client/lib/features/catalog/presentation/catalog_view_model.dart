import '../../../core/models/erp_exception.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';

class CatalogViewModel {
  CatalogViewModel(this._repository) : _owner = _repository.identity {
    reload();
  }
  final CatalogRepository _repository;
  final Object _owner;
  bool _disposed = false;
  Object? _loadedScope;
  late Future<CatalogSnapshot> _result;
  Future<CatalogSnapshot> get result => _result;
  Object get owner => _owner;
  Object get scope => (_owner, _repository.scope);
  bool isCurrent(Object value) =>
      !_disposed &&
      _owner == _repository.identity &&
      _repository.scope != null &&
      _loadedScope == _repository.scope &&
      value == scope;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Future<CatalogSnapshot> reload() {
    if (_disposed ||
        _owner != _repository.identity ||
        _repository.scope == null) {
      _result = Future<CatalogSnapshot>.error(_changed);
      _result.ignore();
      return _result;
    }
    final scope = _repository.scope;
    _result = _read(scope!);
    _result.ignore();
    return _result;
  }

  Future<CatalogSnapshot> _read(Object scope) async {
    final value = await _repository.catalog();
    if (_disposed ||
        _owner != _repository.identity ||
        scope != _repository.scope) {
      throw _changed;
    }
    _loadedScope = scope;
    return value;
  }

  void dispose() => _disposed = true;
}
