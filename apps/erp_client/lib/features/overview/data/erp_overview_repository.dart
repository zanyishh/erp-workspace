import '../../../core/models/erp_exception.dart';
import '../../../core/models/erp_models.dart';
import '../../../erp_api.dart' show ErpApi;
import 'overview_repository.dart';

class ErpOverviewRepository implements OverviewRepository {
  ErpOverviewRepository({required this._api, required this.company});
  final ErpApi _api;
  final String company;
  @override
  Object? get scope => _api.accessReady
      ? (_api, _api.baseUri, _api.account, company, _api.accessRevision)
      : null;

  Future<T> _read<T>(Future<T> Function() read) async {
    final owner = scope;
    if (owner == null) {
      throw _changed;
    }
    final value = await read();
    if (owner != scope) {
      throw _changed;
    }
    return value;
  }

  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );

  @override
  Future<ErpSnapshot> snapshot(ReportingPeriod period) => _read(() async {
    final value = await _api.snapshot(period, selectedCompany: company);
    if (value.company != company) {
      throw const ErpException('ERPNext returned another company overview.');
    }
    return ErpSnapshot(
      company: value.company,
      currency: value.currency,
      counts: Map.unmodifiable(value.counts),
      customers: value.customers,
      suppliers: value.suppliers,
      warehouses: value.warehouses,
      billed: value.billed,
      unpaidInvoices: value.unpaidInvoices,
      sales: List.unmodifiable(value.sales),
      activity: List.unmodifiable(value.activity),
    );
  });

  @override
  Future<List<ErpRecord>> records(
    ErpModule module,
    ReportingPeriod period, {
    String query = '',
    int start = 0,
    bool unpaidOnly = false,
  }) => _read(
    () async => List.unmodifiable(
      await _api.records(
        module,
        company: company,
        period: period,
        query: query,
        start: start,
        unpaidOnly: unpaidOnly,
      ),
    ),
  );
}
