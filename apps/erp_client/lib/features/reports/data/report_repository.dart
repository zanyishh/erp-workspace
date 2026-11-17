import '../models/native_reports.dart';
import '../models/report_definition.dart';

abstract interface class ReportRepository {
  Object get identity;
  Object? get scope;
  Future<ReportDefinition> definition();
  Future<NativeReportResult> run(Map<String, dynamic> filters);
  Future<void> queue(Map<String, dynamic> filters);
  Future<List<Map<String, dynamic>>> links(
    String type,
    String query, {
    required String reference,
    required String field,
  });
}
