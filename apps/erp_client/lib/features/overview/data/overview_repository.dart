import '../../../core/models/erp_models.dart';

abstract interface class OverviewRepository {
  Object? get scope;
  Future<ErpSnapshot> snapshot(ReportingPeriod period);
  Future<List<ErpRecord>> records(
    ErpModule module,
    ReportingPeriod period, {
    String query = '',
    int start = 0,
    bool unpaidOnly = false,
  });
}
