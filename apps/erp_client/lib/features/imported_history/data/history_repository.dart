import '../models/history_models.dart';

abstract interface class ImportedHistoryRepository {
  Object get identity;
  Object? get scope;
  bool get canReadProduction;
  Future<HistorySummary> summary();
  Future<HistoryPage> records(
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  });
  Future<HistoryDetail> detail(String name);
  Future<OriginalProductionPage> production({
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  });
  Future<HistoryChoicesPage> options(
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  });
  Future<OriginalRecordData> printData(String name);
}
