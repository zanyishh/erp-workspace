import '../../../core/models/erp_exception.dart';
import '../../../core/models/native_models.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';

class GroupChangeIntent {
  GroupChangeIntent._(
    this._model,
    this._scope,
    this.groupType,
    List<Map<String, String>> values,
  ) : records = List.unmodifiable(
        values.map((row) => Map<String, String>.unmodifiable(row)),
      );
  final Object _model, _scope;
  final String groupType;
  final List<Map<String, String>> records;
  bool _used = false;
}

class NativeRecordsViewModel {
  NativeRecordsViewModel(this._repository, {required this._type, this.company})
    : _owner = _repository.identity {
    reload();
  }
  final CatalogRepository _repository;
  final Object _owner;
  final String? company;
  NativeType _type;
  NativeType get type => _type;
  int _start = 0, _generation = 0;
  String _query = '';
  String? _openedRecord;
  bool _selecting = false, _disposed = false;
  final _selected = <String, String>{};
  Object? _groupToken, _loadedScope;
  NativeRecordPage? _page;
  late Future<NativeRecordPage> _result;
  Future<NativeRecordPage> get result => _result;
  Object get scope => (_owner, _repository.scope, _type.name);
  int get start => _start;
  String get query => _query;
  bool get selecting => _selecting && _validRows;
  bool get savingGroup => !_disposed && _groupToken != null;
  bool get selectionLimitReached => _validRows && _selected.length == 50;
  String? get openedRecord => _validRows ? _openedRecord : null;
  Map<String, String> get selected =>
      Map.unmodifiable(_validRows ? _selected : <String, String>{});
  String? get groupType => switch (_type.name) {
    'Customer' => 'Customer Group',
    'Supplier' => 'Supplier Group',
    'Item' => 'Item Group',
    _ => null,
  };
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool get active => _active;
  bool get _validRows => _active && _loadedScope == _repository.scope;
  void _requireActive() {
    if (!_active) {
      throw _changed;
    }
  }

  bool _current(int at, Object scope) =>
      _active && at == _generation && scope == _repository.scope;
  void _clearSelection() {
    _selected.clear();
    _selecting = false;
  }

  Future<NativeRecordPage> _fetch(
    int at,
    Object scope,
    String query,
    int start,
  ) async {
    final page = await _repository.records(
      _type.name,
      query: query,
      start: start,
    );
    if (!_current(at, scope)) {
      throw _changed;
    }
    _page = page;
    _loadedScope = scope;
    return page;
  }

  Future<NativeRecordPage> reload({String? query, bool reset = false}) {
    if (!_active) {
      _result = Future<NativeRecordPage>.error(_changed);
      _result.ignore();
      return _result;
    }
    if (_loadedScope != null && _loadedScope != _repository.scope) {
      _clearSelection();
    }
    final next = (query ?? _query).trim();
    if (reset || next != _query) {
      _start = 0;
      _openedRecord = null;
    }
    _query = next;
    _result = _fetch(++_generation, _repository.scope!, _query, _start);
    _result.ignore();
    return _result;
  }

  Future<NativeRecordPage> nextPage({String? query}) {
    _requireActive();
    _start += 50;
    return reload(query: query);
  }

  Future<NativeRecordPage> previousPage({String? query}) {
    _requireActive();
    _start = (_start - 50).clamp(0, _start);
    return reload(query: query);
  }

  bool opened(String? name) {
    if (!_active || (name == null ? !_type.canCreate : !_validRows)) {
      return false;
    }
    _openedRecord = name;
    return true;
  }

  void toggleSelecting() {
    if (!_validRows || savingGroup || !_type.canGroup || company == null) {
      return;
    }
    _selecting = !_selecting;
    _selected.clear();
  }

  bool toggle(String name, String modified) {
    if (!_validRows || !_selecting || savingGroup) {
      return false;
    }
    if (_selected.containsKey(name)) {
      _selected.remove(name);
      return true;
    }
    if (_selected.length == 50 ||
        !_page!.rows.any(
          (row) => row['name'] == name && row['modified'] == modified,
        )) {
      return false;
    }
    _selected[name] = modified;
    return true;
  }

  GroupChangeIntent? prepareGroupChange() {
    final group = groupType;
    if (!_validRows ||
        savingGroup ||
        !_type.canGroup ||
        company == null ||
        group == null ||
        _selected.isEmpty) {
      return null;
    }
    return GroupChangeIntent._(this, _repository.scope!, group, [
      for (final entry in _selected.entries)
        {'name': entry.key, 'modified': entry.value},
    ]);
  }

  Future<List<Map<String, dynamic>>> groups(String query) async {
    _requireActive();
    final group = groupType;
    if (group == null) {
      return const [];
    }
    return _repository.groups(_type.name, group, query);
  }

  Future<int?> applyGroup(GroupChangeIntent intent, String group) async {
    if (!_validRows ||
        savingGroup ||
        !_type.canGroup ||
        intent._used ||
        intent._model != this ||
        intent._scope != _repository.scope ||
        group.trim().isEmpty) {
      return null;
    }
    intent._used = true;
    final token = Object(), scope = _repository.scope;
    _groupToken = token;
    try {
      final count = await _repository.reclassify(
        _type.name,
        intent.records,
        group.trim(),
      );
      if (!_active || scope != _repository.scope) {
        return null;
      }
      _clearSelection();
      reload();
      return count;
    } catch (_) {
      if (!_active || scope != _repository.scope) {
        return null;
      }
      rethrow;
    } finally {
      if (identical(_groupToken, token)) {
        _groupToken = null;
      }
    }
  }

  Future<void> revalidate() async {
    _requireActive();
    _clearSelection();
    _query = '';
    _start = 0;
    _openedRecord = null;
    final at = ++_generation, scope = _repository.scope!;
    _result = _revalidate(at, scope);
    _result.ignore();
    await _result;
  }

  Future<NativeRecordPage> _revalidate(int at, Object scope) async {
    final catalog = await _repository.catalog();
    if (!_current(at, scope)) {
      throw _changed;
    }
    final fresh = catalog.types
        .where((type) => type.name == _type.name)
        .firstOrNull;
    if (fresh == null) {
      throw const ErpException('This record type is no longer available.');
    }
    _type = fresh;
    return _fetch(at, scope, _query, _start);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _clearSelection();
    _page = null;
    _query = '';
    _openedRecord = null;
  }
}
