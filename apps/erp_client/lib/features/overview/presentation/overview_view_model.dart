import 'dart:async';

import '../../../core/models/erp_models.dart';
import '../data/overview_repository.dart';

class OverviewViewModel {
  OverviewViewModel(this._repository, {this.period = ReportingPeriod.month}) {
    reload();
  }
  final OverviewRepository _repository;
  final ReportingPeriod period;
  late Future<ErpSnapshot> _result;
  bool _disposed = false;
  Future<ErpSnapshot> get result => _result;
  void _active() {
    if (_disposed) {
      throw StateError('This overview has been disposed.');
    }
  }

  Future<ErpSnapshot> reload() {
    _active();
    _result = _repository.snapshot(period);
    // Preserve the original failing future for the view, including when a read
    // fails before the next frame subscribes to it.
    unawaited(_result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return _result;
  }

  Future<List<ErpRecord>> records(
    ErpModule module, {
    String query = '',
    int start = 0,
    bool unpaidOnly = false,
  }) async {
    _active();
    return _repository.records(
      module,
      period,
      query: query,
      start: start,
      unpaidOnly: unpaidOnly,
    );
  }

  void dispose() => _disposed = true;
}
