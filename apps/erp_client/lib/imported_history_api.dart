part of 'erp_api.dart';

/// Immutable historical reads; the server authorizes company and financial scope.
mixin _ImportedHistoryApi {
  Future<Map<String, dynamic>> _industry(
    String module,
    String operation,
    Map<String, Object?> args,
  );

  Future<Map<String, dynamic>> importedHistorySummary(String company) =>
      _industry('migration.api', 'summary', {'company': company});

  Future<Map<String, dynamic>> importedHistoryRecords(
    String company,
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) => _industry('migration.api', 'records', {
    'company': company,
    'family': family,
    'query': query,
    'start': start,
    'page_length': pageLength,
    'filters': filters,
  });

  Future<Map<String, dynamic>> originalProductionSummary(
    String company, {
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  }) => _industry('migration.production_reports', 'summary', {
    'company': company,
    'group_by': groupBy,
    'filters': filters,
    'start': start,
    'page_length': pageLength,
  });

  Future<Map<String, dynamic>> importedHistoryDetail(
    String company,
    String name,
  ) => _industry('migration.api', 'detail', {'company': company, 'name': name});

  Future<Map<String, dynamic>> importedSharedCash(
    String company, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) => _industry('migration.api', 'shared_cash', {
    'company': company,
    'query': query,
    'start': start,
    'page_length': pageLength,
    'filters': filters,
  });

  Future<Map<String, dynamic>> importedHistoryFilterOptions(
    String company,
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  }) => _industry('migration.api', 'filter_options', {
    'company': company,
    'family': family,
    'field': field,
    'query': query,
    'start': start,
    'filters': filters,
  });

  Future<Map<String, dynamic>> importedRecordPrintData(
    String company,
    String name,
  ) => _industry('migration.printing', 'record_data', {
    'company': company,
    'name': name,
  });

  Future<Map<String, dynamic>> importedInvoicePrintData(
    String company,
    String name,
  ) => _industry('migration.api', 'invoice_print_data', {
    'company': company,
    'name': name,
  });
}
