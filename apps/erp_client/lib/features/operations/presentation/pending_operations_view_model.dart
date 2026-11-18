import '../../../core/models/erp_exception.dart';
import '../data/operation_repository.dart';
import '../models/operation_reference.dart';

enum _Action { check, close, dismiss }

class PendingOperationsViewModel {
  PendingOperationsViewModel(this._repository);
  final OperationRepository _repository;
  final _rows = <OperationReference>[];
  final _working = <String, Object>{};
  Object? _loadedScope;
  String? _error;
  bool _loading = true, _more = false, _disposed = false;
  int _page = 0, _generation = 0;
  List<OperationReference> get rows => List.unmodifiable(_rows);
  String? get error => _error;
  bool get loading => _loading;
  bool get more => _more;
  int get page => _page;
  bool isWorking(String id) => _working.containsKey(id);
  bool _active(int at) => !_disposed && at == _generation;
  bool _current(int at, Object? scope) =>
      _active(at) && scope != null && scope == _repository.scope;
  static const _accessChanged =
      'Access changed. Reload pending operations before continuing.';

  Future<void> load({bool clear = false, bool rethrowFailure = false}) async {
    if (_disposed) return;
    final at = ++_generation, scope = _repository.scope;
    _loading = true;
    _error = null;
    if (clear || _loadedScope != scope) _rows.clear();
    if (_loadedScope != scope) _working.clear();
    _loadedScope = scope;
    try {
      // The server filters a raw 50-row page for permissions; visible length is not the cursor.
      final data = await _repository.load(start: _page * 50);
      if (!_active(at)) return;
      if (!_current(at, scope)) {
        _rows.clear();
        _error = _accessChanged;
        return;
      }
      _rows
        ..clear()
        ..addAll(data.rows);
      _more = data.hasMore;
    } catch (error) {
      if (!_active(at)) return;
      _error = scope != _repository.scope ? _accessChanged : error.toString();
      if (scope != _repository.scope ||
          error is ErpException &&
              (error.permissionDenied || error.sessionExpired)) {
        _rows.clear();
      }
      if (rethrowFailure) rethrow;
    } finally {
      if (_active(at)) _loading = false;
    }
  }

  Future<void> revalidate() {
    _page = 0;
    return load(clear: true, rethrowFailure: true);
  }

  Future<void> nextPage() async {
    if (_loading || !_more || _disposed) return;
    _page++;
    await load(clear: true);
  }

  Future<void> previousPage() async {
    if (_loading || _page == 0 || _disposed) return;
    _page--;
    await load(clear: true);
  }

  bool canClose(OperationReference row) => row.state == 'prepared';
  bool canDismiss(OperationReference row) =>
      row.state == 'closed' || row.state == 'completed';
  Future<void> checkStatus(String id) => _act(id, _Action.check);
  Future<void> closeUnposted(String id) => _act(id, _Action.close);
  Future<void> dismiss(String id) => _act(id, _Action.dismiss);

  Future<void> _act(String id, _Action action) async {
    if (_disposed || _working.containsKey(id)) return;
    final scope = _repository.scope, at = _generation;
    if (scope == null || scope != _loadedScope) {
      _rows.clear();
      _working.clear();
      _error = _accessChanged;
      return;
    }
    final index = _rows.indexWhere((row) => row.requestId == id);
    if (index < 0 ||
        action == _Action.close && !canClose(_rows[index]) ||
        action == _Action.dismiss && !canDismiss(_rows[index])) {
      return;
    }
    final token = Object();
    _working[id] = token;
    _error = null;
    try {
      if (action == _Action.dismiss) {
        await _repository.acknowledge(id);
        if (_current(at, scope)) {
          _rows.removeWhere((row) => row.requestId == id);
        }
      } else {
        final result = action == _Action.close
            ? await _repository.closeUnposted(id)
            : await _repository.status(id);
        if (_current(at, scope)) {
          final index = _rows.indexWhere((row) => row.requestId == id);
          if (index >= 0) _rows[index] = result;
        }
      }
    } catch (error) {
      if (_current(at, scope)) {
        _error = error.toString();
        if (error is ErpException && error.permissionDenied) {
          _rows.removeWhere((row) => row.requestId == id);
        }
      }
    } finally {
      if (_active(at) && scope != _repository.scope) {
        _rows.clear();
        _error = _accessChanged;
      }
      // A refresh may supersede the result, but must retire this action's busy state.
      if (!_disposed && identical(_working[id], token)) _working.remove(id);
    }
  }

  String title(OperationReference row) => switch (row.kind) {
    'invoice' => 'Save invoice draft',
    'reconciliation' => 'Apply payment',
    'knitting' => (row.action ?? 'Knitting entry').replaceAll('_', ' '),
    _ => '${row.action ?? 'Save'} ${row.doctype ?? 'record'}',
  };
  String statusLabel(OperationReference row) => switch (row.state) {
    'completed' => 'Completed',
    'closed' => 'Closed without posting',
    _ => 'Outcome not confirmed',
  };
  String? reconciliationNotice(OperationReference row) =>
      row.kind == 'reconciliation' && row.result.hasValues
      ? 'Payment ${row.result.payment} applied to ${row.result.invoice}. Reopen reconciliation for current balances.'
      : null;
  void dispose() {
    _disposed = true;
    _generation++;
    _rows.clear();
    _working.clear();
  }
}
