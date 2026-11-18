import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/native_reports.dart';
import '../models/report_definition.dart';
import '../models/report_values.dart';
import 'report_repository.dart';

class ErpReportRepository implements ReportRepository {
  ErpReportRepository({required this._api, required this.name, this.company});
  final ErpApi _api;
  final String name;
  final String? company;
  @override
  Object get identity => (_api, _api.baseUri, _api.account, company, name);
  @override
  Object? get scope =>
      _api.accessReady ? (identity, _api.accessRevision) : null;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Future<T> _read<T>(Future<T> Function() read) async {
    final captured = scope;
    if (captured == null) throw _changed;
    final result = await read();
    if (captured != scope) throw _changed;
    return result;
  }

  @override
  Future<ReportDefinition> definition() => _read(
    () async => ReportDefinition.fromJson(
      await _api.reportDefinition(name, company: company),
    ),
  );
  @override
  Future<NativeReportResult> run(Map<String, dynamic> filters) =>
      _read(() => _api.runReport(name, immutableReportMap(filters)));
  @override
  Future<void> queue(Map<String, dynamic> filters) =>
      _read(() => _api.queueReport(name, immutableReportMap(filters)));
  @override
  Future<List<Map<String, dynamic>>> links(
    String type,
    String query, {
    required String reference,
    required String field,
  }) => _read(
    () async => List.unmodifiable(
      (await _api.searchLinks(
        type,
        query,
        parent: reference,
        field: field,
      )).map(immutableReportMap),
    ),
  );
}
