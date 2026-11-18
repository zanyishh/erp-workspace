import '../../../core/models/erp_exception.dart';
import '../data/invoice_repository.dart';

class InvoiceRegisterViewModel {
  InvoiceRegisterViewModel(this._repository) : _owner = _repository.identity {
    reload();
  }
  final InvoiceRegisterRepository _repository;
  final Object _owner;
  static const pageSize = 25;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  bool _disposed = false, _loading = false;
  int _generation = 0, _start = 0;
  String _query = '', _status = 'All';
  InvoiceRegisterPage? _page;
  // Retained builders can still render a prior response during the handoff.
  Expando<Object> _acceptedScopes = Expando<Object>();
  Object? _pageScope, _resultScope;
  late Future<InvoiceRegisterPage> _result;
  late final Future<InvoiceRegisterPage> _unavailable = () {
    final future = Future<InvoiceRegisterPage>.error(_changed);
    future.ignore();
    return future;
  }();
  Future<InvoiceRegisterPage> get result =>
      _active && _resultScope == viewScope ? _result : _unavailable;
  InvoiceRegisterPage? get loadedPage => canUse(_page) ? _page : null;
  Object get scope => (_owner, _repository.scope);
  Object get viewScope => (scope, _query, _status, _start);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && value == scope;
  String get query => _query;
  String get status => _status;
  int get start => _start;
  bool canUse(InvoiceRegisterPage? value) =>
      _active &&
      value != null &&
      _page != null &&
      _acceptedScopes[value] == viewScope &&
      _pageScope == viewScope;
  bool canCreate(InvoiceRegisterPage? value) =>
      canUse(value) && _page!.canCreate;
  bool canManageSettings(InvoiceRegisterPage? value) =>
      canUse(value) && _page!.canManageSettings;
  bool canOpen(
    InvoiceRegisterPage value,
    String name, {
    bool preview = false,
  }) =>
      canUse(value) &&
      value.rows.any((row) => row['name'] == name) &&
      _page!.rows.any(
        (row) => row['name'] == name && (!preview || row['can_print'] == true),
      );
  void _forget() {
    _page = null;
    _pageScope = null;
    _acceptedScopes = Expando<Object>();
  }

  Future<InvoiceRegisterPage> reload({bool first = false}) {
    if (first) _start = 0;
    final request = ++_generation, captured = viewScope;
    _resultScope = captured;
    if (_pageScope != captured) _forget();
    _loading = true;
    _result = _active ? _read(request, captured) : Future.error(_changed);
    _result.ignore();
    return _result;
  }

  Future<InvoiceRegisterPage> _read(int request, Object captured) async {
    bool current() =>
        _active && request == _generation && captured == viewScope;
    try {
      final value = await _repository.register(
        query: _query,
        status: _status,
        start: _start,
        pageSize: pageSize,
      );
      if (!current()) throw _changed;
      _acceptedScopes[value] = captured;
      _page = value;
      _pageScope = captured;
      return value;
    } catch (error) {
      if (!current()) throw _changed;
      if (error is ErpException &&
          (error.permissionDenied || error.sessionExpired)) {
        _forget();
      }
      rethrow;
    } finally {
      if (request == _generation) _loading = false;
    }
  }

  Future<InvoiceRegisterPage> search(String value) {
    _query = value.trim();
    return reload(first: true);
  }

  Future<InvoiceRegisterPage> chooseStatus(String value) {
    if (!_active || !(_page?.statuses ?? ['All', _status]).contains(value)) {
      return result;
    }
    _status = value;
    return reload(first: true);
  }

  Future<InvoiceRegisterPage> showAll({String query = ''}) {
    _query = query;
    _status = 'All';
    return reload(first: true);
  }

  Future<InvoiceRegisterPage> nextPage() {
    if (_loading || !canUse(_page) || !_page!.hasMore) return result;
    _start += pageSize;
    return reload();
  }

  Future<InvoiceRegisterPage> previousPage() {
    if (_loading || !_active || _start == 0) return result;
    _start = (_start - pageSize).clamp(0, _start);
    return reload();
  }

  Future<void> revalidate() async {
    await showAll();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _forget();
  }
}
