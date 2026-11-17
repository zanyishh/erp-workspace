import 'package:flutter/foundation.dart';

import '../../../core/models/access_source.dart';
import '../data/access_repository.dart';

class AccessGateViewModel extends ChangeNotifier {
  AccessGateViewModel(
    this._repository, {
    required this._revalidate,
    bool validateInitially = false,
  }) {
    _account = source.account;
    _revision = source.accessRevision;
    _ready = source.accessReady;
    _valid = _ready && !validateInitially;
    _repository.addListener(_changed);
  }
  final AccessRepository _repository;
  Future<void> Function() _revalidate;
  late String _account;
  late int _revision;
  late bool _ready, _valid;
  bool _disposed = false;
  int _generation = 0;
  String? _error;
  AccessSource get source => _repository.source;
  String get account => _account;
  int get revision => _revision;
  bool get ready => _ready;
  bool get valid => !_disposed && _valid;
  String? get error => _error;
  void updateReload(Future<void> Function() revalidate) {
    _revalidate = revalidate;
  }

  void _changed() {
    if (_disposed ||
        _account == source.account &&
            _revision == source.accessRevision &&
            _ready == source.accessReady) {
      return;
    }
    _account = source.account;
    _revision = source.accessRevision;
    _ready = source.accessReady;
    _generation++;
    _valid = false;
    _error = null;
    notifyListeners();
    if (_ready) refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final at = ++_generation,
        account = source.account,
        revision = source.accessRevision;
    try {
      await _revalidate();
      if (!_disposed &&
          at == _generation &&
          account == source.account &&
          revision == source.accessRevision &&
          source.accessReady) {
        _valid = true;
        _error = null;
        notifyListeners();
      }
    } catch (error) {
      if (!_disposed &&
          at == _generation &&
          account == source.account &&
          revision == source.accessRevision) {
        _error = error.toString();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _valid = false;
    _repository.removeListener(_changed);
    super.dispose();
  }
}
