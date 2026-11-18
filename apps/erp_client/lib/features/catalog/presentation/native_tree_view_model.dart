import '../../../core/models/erp_exception.dart';
import '../../../core/models/native_models.dart';
import '../data/native_tree_repository.dart';
import '../models/catalog_models.dart';

class TreeChangeIntent {
  TreeChangeIntent._(this._model, this._scope, this.node, this.action);
  final Object _model, _scope;
  final NativeTreeNode node;
  final String action;
  bool _used = false;
}

class NativeTreeViewModel {
  NativeTreeViewModel(
    this._repository, {
    required this.type,
    this.company,
    this.parent,
  }) : _owner = _repository.identity {
    reload();
  }
  final NativeTreeRepository _repository;
  final Object _owner;
  final NativeType type;
  final String? company, parent;
  int _start = 0, _generation = 0;
  bool _disposed = false;
  Object? _loadedScope, _changeToken;
  NativeTreePage? _page;
  late Future<NativeTreePage> _result;
  Future<NativeTreePage> get result => _result;
  Object get scope => (_owner, _repository.scope, type.name, parent);
  int get start => _start;
  bool get changing => !_disposed && _changeToken != null;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool get _validRows => _active && _loadedScope == _repository.scope;
  bool canOpen(String? name) =>
      _validRows && (name != null || _page!.canCreate);
  void _requireActive() {
    if (!_active) {
      throw _changed;
    }
  }

  Future<NativeTreePage> reload() {
    if (!_active) {
      _result = Future<NativeTreePage>.error(_changed);
      _result.ignore();
      return _result;
    }
    _result = _read(++_generation, _repository.scope!, _start);
    _result.ignore();
    return _result;
  }

  Future<NativeTreePage> _read(int at, Object scope, int start) async {
    final page = await _repository.tree(
      type.name,
      parent: parent,
      start: start,
    );
    if (!_active || at != _generation || scope != _repository.scope) {
      throw _changed;
    }
    _page = page;
    _loadedScope = scope;
    return page;
  }

  Future<NativeTreePage> nextPage() {
    _requireActive();
    _start += 50;
    return reload();
  }

  Future<NativeTreePage> previousPage() {
    _requireActive();
    _start = (_start - 50).clamp(0, _start);
    return reload();
  }

  bool _allowed(NativeTreeNode node, String action) =>
      _validRows &&
      node.modified != null &&
      (action == 'rename' && _page!.canRename ||
          action == 'delete' && _page!.canDelete) &&
      _page!.nodes.any(
        (current) =>
            current.name == node.name && current.modified == node.modified,
      );
  TreeChangeIntent? prepareChange(NativeTreeNode node, String action) {
    if (changing || !_allowed(node, action)) {
      return null;
    }
    return TreeChangeIntent._(this, _repository.scope!, node, action);
  }

  Future<bool> change(TreeChangeIntent intent, {String? newName}) async {
    final rename = intent.action == 'rename', label = newName?.trim();
    if (changing ||
        intent._used ||
        intent._model != this ||
        intent._scope != _repository.scope ||
        !_allowed(intent.node, intent.action) ||
        rename &&
            (label == null || label.isEmpty || label == intent.node.name)) {
      return false;
    }
    intent._used = true;
    final token = Object(), scope = _repository.scope;
    _changeToken = token;
    try {
      await _repository.changeTree(
        type.name,
        intent.node.name,
        intent.node.modified!,
        intent.action,
        newName: rename ? label : null,
      );
      if (!_active || scope != _repository.scope) {
        return false;
      }
      _start = 0;
      reload();
      return true;
    } catch (_) {
      if (!_active || scope != _repository.scope) {
        return false;
      }
      rethrow;
    } finally {
      if (identical(_changeToken, token)) {
        _changeToken = null;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _page = null;
  }
}
