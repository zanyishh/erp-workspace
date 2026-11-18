import 'dart:async';

import '../../../core/models/erp_models.dart';
import '../data/module_record_repository.dart';

class ModuleBrowserViewModel {
  ModuleBrowserViewModel(
    this._repository, {
    required this.company,
    required this._currency,
    required this.module,
    this.scope,
  }) {
    reload();
  }
  final ModuleRecordRepository _repository;
  final String company;
  String _currency;
  String get currency => _currency;
  final ErpModule module;
  final Object? scope;
  String _query = '';
  int _start = 0;
  String? _openedRecord;
  bool _disposed = false;
  late Future<List<ErpRecord>> _result;
  String get query => _query;
  int get start => _start;
  String? get openedRecord => _openedRecord;
  Future<List<ErpRecord>> get result => _result;
  void _active() {
    if (_disposed) {
      throw StateError('This browser has been disposed.');
    }
  }

  Future<List<ErpRecord>> reload({String? query, bool reset = false}) {
    _active();
    final next = (query ?? _query).trim();
    if (reset || next != _query) {
      _start = 0;
      _openedRecord = null;
    }
    _query = next;
    _result = _repository.load(_query, _start);
    unawaited(_result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return _result;
  }

  Future<List<ErpRecord>> nextPage({String? query}) {
    _active();
    _start += 50;
    return reload(query: query);
  }

  Future<List<ErpRecord>> previousPage({String? query}) {
    _active();
    _start = (_start - 50).clamp(0, _start);
    return reload(query: query);
  }

  void opened(String name) {
    _active();
    _openedRecord = name;
  }

  void updateCurrency(String value) {
    _active();
    _currency = value;
  }

  void dispose() => _disposed = true;
}
