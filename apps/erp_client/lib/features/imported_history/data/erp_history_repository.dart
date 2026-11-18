import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/history_models.dart';
import 'history_repository.dart';

class ErpImportedHistoryRepository implements ImportedHistoryRepository {
  ErpImportedHistoryRepository({required this._api, required this.company});
  final ErpApi _api;
  final String company;
  @override
  Object get identity => (_api, _api.baseUri, _api.account, company);
  @override
  Object? get scope =>
      _api.accessReady ? (identity, _api.accessRevision) : null;
  @override
  bool get canReadProduction =>
      _api.accessReady &&
      _api.contextFor(company)?.canReadImportedHistory == true;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Future<T> _read<T>(Future<T> Function() read) async {
    final captured = scope;
    if (captured == null) throw _changed;
    final value = await read();
    if (captured != scope) throw _changed;
    return value;
  }

  @override
  Future<HistorySummary> summary() => _read(
    () async => HistorySummary.fromJson(
      await _api.importedHistorySummary(company),
      company: company,
    ),
  );
  @override
  Future<HistoryPage> records(
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) {
    final snapshot = immutableJsonMap(filters);
    return _read(
      () async => HistoryPage.fromJson(
        family == 'shared_cash'
            ? await _api.importedSharedCash(
                company,
                query: query,
                start: start,
                pageLength: pageLength,
                filters: snapshot,
              )
            : await _api.importedHistoryRecords(
                company,
                family,
                query: query,
                start: start,
                pageLength: pageLength,
                filters: snapshot,
              ),
        company: company,
        family: family,
        start: start,
        pageLength: pageLength,
        filters: snapshot,
      ),
    );
  }

  @override
  Future<HistoryDetail> detail(String name) => _read(
    () async => HistoryDetail.fromJson(
      await _api.importedHistoryDetail(company, name),
      company: company,
      name: name,
    ),
  );
  @override
  Future<OriginalProductionPage> production({
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  }) {
    final snapshot = immutableJsonMap(filters);
    return _read(() async {
      if (!canReadProduction) {
        throw const ErpException('Your access to original production changed.');
      }
      return OriginalProductionPage.fromJson(
        await _api.originalProductionSummary(
          company,
          groupBy: groupBy,
          filters: snapshot,
          start: start,
          pageLength: pageLength,
        ),
        company: company,
        groupBy: groupBy,
        start: start,
        pageLength: pageLength,
        filters: snapshot,
      );
    });
  }

  @override
  Future<HistoryChoicesPage> options(
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  }) {
    final snapshot = immutableJsonMap(filters);
    return _read(
      () async => HistoryChoicesPage.fromJson(
        await _api.importedHistoryFilterOptions(
          company,
          family,
          field,
          query: query,
          start: start,
          filters: snapshot,
        ),
        company: company,
        family: family,
        field: field,
        start: start,
      ),
    );
  }

  @override
  Future<OriginalRecordData> printData(String name) => _read(
    () async => OriginalRecordData.fromJson(
      await _api.importedRecordPrintData(company, name),
      company: company,
      name: name,
    ),
  );
}
