import '../../../core/models/erp_exception.dart';
import '../../../core/models/workspace_context.dart';
import '../data/workspace_repository.dart';

class WorkspaceViewModel {
  WorkspaceViewModel(this._repository);
  final WorkspaceRepository _repository;
  WorkspaceContext? _context;
  Object? _loadedOwner, _loadedScope, _selection;
  String? _error;
  int _generation = 0;
  bool _disposed = false, _loading = false;
  WorkspaceContext? get context =>
      !_disposed && _loadedOwner == _repository.identity ? _context : null;
  String? get error => _error;
  bool get loading => _loading;
  bool get selecting => !_disposed && _selection != null;
  bool _current(int at, Object owner) =>
      !_disposed && at == _generation && owner == _repository.identity;
  void adopt(WorkspaceContext value) {
    if (_disposed) return;
    _generation++;
    _context = value;
    _loadedOwner = _repository.identity;
    _loadedScope = _repository.accessScope;
    _loading = false;
    _error = null;
  }

  Future<WorkspaceContext?> load({String? company}) =>
      _read(() => _repository.load(company: company));
  Future<WorkspaceContext?> current(String? company) async {
    if (_disposed) return null;
    final owner = _repository.identity;
    try {
      final value = await _repository.current(company);
      return !_disposed && owner == _repository.identity ? value : null;
    } catch (_) {
      if (_disposed || owner != _repository.identity) return null;
      rethrow;
    }
  }

  Future<WorkspaceContext?> _read(
    Future<WorkspaceContext> Function() read,
  ) async {
    if (_disposed) return null;
    final at = ++_generation, owner = _repository.identity;
    _loading = true;
    _error = null;
    try {
      final value = await read();
      if (!_current(at, owner)) return null;
      _context = value;
      _loadedOwner = owner;
      _loadedScope = _repository.accessScope;
      return value;
    } catch (error) {
      if (!_current(at, owner)) return null;
      _error = error.toString();
      rethrow;
    } finally {
      if (_current(at, owner)) _loading = false;
    }
  }

  Future<WorkspaceContext?> select(String company) async {
    if (_disposed || _selection != null) return null;
    final owner = _repository.identity;
    if (_loadedOwner != owner ||
        _loadedScope == null ||
        _loadedScope != _repository.accessScope) {
      _error = 'Reload workspace access before choosing a company.';
      return null;
    }
    if (_context?.company == company) return null;
    if (!_context!.companies.any((row) => row['name'] == company)) {
      throw const ErpException(
        'This company is unavailable.',
        permissionDenied: true,
      );
    }
    final token = Object();
    _selection = token;
    _error = null;
    try {
      final value = await _repository.select(company);
      if (_disposed ||
          owner != _repository.identity ||
          !identical(_selection, token)) {
        return null;
      }
      // A confirmed selection supersedes reads begun while the preference write was pending.
      adopt(value);
      return value;
    } catch (error) {
      if (_disposed || owner != _repository.identity) return null;
      _error = error.toString();
      rethrow;
    } finally {
      if (identical(_selection, token)) _selection = null;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _context = null;
    _selection = null;
  }

  void clear() {
    _generation++;
    _context = null;
    _loadedOwner = null;
    _loadedScope = null;
    _error = null;
    _loading = false;
  }
}
