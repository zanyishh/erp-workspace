import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import 'history_filter_values.dart';

String _text(Object? value) => value?.toString() ?? '';
List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List || value.any((row) => row is! Map)) {
    throw const ErpException(
      'The imported record returned an unexpected format.',
    );
  }
  return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

void _scope(Map<String, dynamic> data, String company) {
  if (data['version'] != 1 || data['company'] != company) {
    throw const ErpException(
      'The imported record returned an unexpected scope. Refresh and try again.',
    );
  }
}

bool _validProductionTotals(Map data) {
  final count = data['source_record_count'];
  if (count is! int || count < 0) return false;
  for (final key in ['quantity_kg', 'recorded_count']) {
    final value = data[key];
    if (value != null &&
        (value is! String || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value))) {
      return false;
    }
  }
  for (final key in ['missing_quantity_rows', 'missing_count_rows']) {
    final value = data[key];
    if (value is! int || value < 0 || value > count) return false;
  }
  return true;
}

List<Map<String, dynamic>> _printRows(Object? value) {
  if (value is! List || value.any((row) => row is! Map)) {
    throw const FormatException(
      'The original record has invalid print fields.',
    );
  }
  return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

class HistorySummary {
  HistorySummary._(Map<String, dynamic> value) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  late final List<Map<String, dynamic>> families = List.unmodifiable(
    (data['families'] as List).cast<Map<String, dynamic>>(),
  );
  bool get sharedAvailable => data['shared_cash_available'] == true;
  factory HistorySummary.fromJson(
    Map<String, dynamic> data, {
    required String company,
  }) {
    _scope(data, company);
    final choices = _objects(data['families']);
    final keys = choices.map((row) => _text(row['key'])).toSet();
    if (keys.length != choices.length ||
        keys.contains('') ||
        keys.contains('shared_cash') ||
        choices.any((row) => row['label'] is! String)) {
      throw const ErpException('The imported history choices are unavailable.');
    }
    return HistorySummary._(data);
  }
}

class HistoryPage {
  HistoryPage._(
    Map<String, dynamic> value,
    this.filterLabels,
    this.filterFields,
    this.start,
    this.pageLength,
  ) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  final Map<String, String> filterLabels;
  final List<String> filterFields;
  final int start, pageLength;
  late final List<Map<String, dynamic>> rows = List.unmodifiable(
    (data['rows'] as List).cast<Map<String, dynamic>>(),
  );
  late final List<Map<String, dynamic>> cashBalances =
      data['family'] == 'shared_cash'
      ? List.unmodifiable(
          (data['balances'] as List? ?? []).cast<Map<String, dynamic>>(),
        )
      : const [];
  bool get hasMore => data['has_more'] == true;
  int? get rowCount => data['row_count'] as int?;
  factory HistoryPage.fromJson(
    Map<String, dynamic> data, {
    required String company,
    required String family,
    required int start,
    required int pageLength,
    Map<String, dynamic> filters = const {},
  }) {
    _scope(data, company);
    final items = _objects(data['rows']);
    final available = data['available_filters'];
    final labels = parseHistoryFilterLabels(data['filter_labels'], filters);
    if ((available != null &&
            (available is! List ||
                available.any(
                  (key) => !historyFilterLabels.containsKey(key),
                ))) ||
        (data['row_count'] != null &&
            (data['row_count'] is! int || (data['row_count'] as int) < 0))) {
      throw const ErpException(
        'The imported filter choices returned an unexpected format.',
      );
    }
    final balances = family == 'shared_cash'
        ? _objects(data['balances'] ?? [])
        : <Map<String, dynamic>>[];
    if (balances.any(
          (row) =>
              row['cash_book_id'] is! String ||
              row['label'] is! String ||
              row['verified'] is! bool,
        ) ||
        balances.map((row) => row['cash_book_id']).toSet().length !=
            balances.length) {
      throw const ErpException(
        'The shared cash controls returned an unexpected format.',
      );
    }
    if (data['family'] != family ||
        data['start'] != start ||
        data['page_length'] != pageLength ||
        data['has_more'] is! bool ||
        items.length > pageLength ||
        items.any(
          (row) =>
              row['name'] is! String ||
              _text(row['name']).isEmpty ||
              row['title'] is! String ||
              row['summary'] != null && row['summary'] is! String,
        ) ||
        items.map((row) => row['name']).toSet().length != items.length ||
        family != 'shared_cash' &&
            items.any((row) => row['family'] != family) ||
        family == 'production' &&
            items.any((row) {
              if (!row.containsKey('production_fields')) return false;
              final fields = row['production_fields'];
              return fields is! Map ||
                  fields.values.any((value) => value is Map || value is List);
            }) ||
        family == 'shared_cash' &&
            (data['shared_scope'] is! Map ||
                (data['shared_scope'] as Map)['cash_is_shared'] != true)) {
      throw const ErpException(
        'The imported register returned an unexpected scope or page.',
      );
    }
    return HistoryPage._(
      data,
      Map.unmodifiable(labels),
      List.unmodifiable(
        available == null
            ? ['source_book']
            : List<String>.from(available as List),
      ),
      start,
      pageLength,
    );
  }
}

class HistoryDetail {
  HistoryDetail._(Map<String, dynamic> value) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  factory HistoryDetail.fromJson(
    Map<String, dynamic> data, {
    required String company,
    required String name,
  }) {
    _scope(data, company);
    if (data['name'] != name) {
      throw const ErpException(
        'The imported record returned an unexpected scope.',
      );
    }
    for (final field in _objects(data['fields'])) {
      if (field['label'] is! String ||
          field['value'] is Map ||
          field['value'] is List) {
        throw const ErpException('This imported detail is unavailable.');
      }
    }
    for (final table in _objects(data['tables'])) {
      if (table['title'] is! String) {
        throw const ErpException('This imported detail is unavailable.');
      }
      final columns = _objects(table['columns']);
      final rows = _objects(table['rows']);
      if (columns.isEmpty && rows.any((row) => row.isNotEmpty) ||
          columns.any((c) => c['key'] is! String || c['label'] is! String) ||
          rows.any(
            (r) =>
                columns.any((c) => r[c['key']] is Map || r[c['key']] is List),
          )) {
        throw const ErpException('This imported table is unavailable.');
      }
    }
    if (data['review_notes'] is! List ||
        (data['review_notes'] as List).any((v) => v is! String)) {
      throw const ErpException('This imported review is unavailable.');
    }
    if (_objects(data['target_links'] ?? []).any(
      (row) =>
          row['doctype'] is! String ||
          _text(row['doctype']).isEmpty ||
          row['name'] is! String ||
          _text(row['name']).isEmpty,
    )) {
      throw const ErpException('The related ERP record is unavailable.');
    }
    return HistoryDetail._(data);
  }
}

class OriginalProductionPage {
  OriginalProductionPage._(
    Map<String, dynamic> value,
    this.filterLabels,
    this.start,
    this.pageLength,
  ) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  final Map<String, String> filterLabels;
  final int start, pageLength;
  late final List<Map<String, dynamic>> rows = List.unmodifiable(
    (data['rows'] as List).cast<Map<String, dynamic>>(),
  );
  Map<String, dynamic> get totals => data['totals'] as Map<String, dynamic>;
  late final List<String> filterFields = List.unmodifiable(
    (data['available_filters'] as List).cast<String>(),
  );
  bool get hasMore => data['has_more'] == true;
  int get rowCount => data['row_count'] as int;
  factory OriginalProductionPage.fromJson(
    Map<String, dynamic> data, {
    required String company,
    required String groupBy,
    required int start,
    required int pageLength,
    Map<String, dynamic> filters = const {},
  }) {
    if (data['version'] != 1 ||
        data['company'] != company ||
        data['family'] != 'production' ||
        data['group_by'] != groupBy ||
        data['start'] != start ||
        data['page_length'] != pageLength) {
      throw const ErpException(
        'The original production report returned an unexpected scope or page.',
      );
    }
    final items = data['rows'], summary = data['totals'];
    final available = data['available_filters'];
    final labels = parseHistoryFilterLabels(data['filter_labels'], filters);
    if (items is! List ||
        items.length > pageLength ||
        summary is! Map ||
        !_validProductionTotals(summary) ||
        data['row_count'] is! int ||
        (data['row_count'] as int) < 0 ||
        data['has_more'] is! bool ||
        available is! List ||
        available.any((key) => !historyFilterLabels.containsKey(key)) ||
        items.any(
          (row) =>
              row is! Map ||
              !_validProductionTotals(row) ||
              row['label'] is! String ||
              (row['value'] is Map || row['value'] is List) ||
              row['drillable'] is! bool ||
              (row['drillable'] == true && row['filters'] is! Map),
        )) {
      throw const ErpException(
        'The original production report returned an unexpected format.',
      );
    }
    return OriginalProductionPage._(
      data,
      Map.unmodifiable(labels),
      start,
      pageLength,
    );
  }
}

class HistoryChoicesPage {
  HistoryChoicesPage._(Map<String, dynamic> value, this.start)
    : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  final int start;
  late final List<Map<String, dynamic>> rows = List.unmodifiable(
    (data['rows'] as List).cast<Map<String, dynamic>>(),
  );
  bool get hasMore => data['has_more'] == true;
  factory HistoryChoicesPage.fromJson(
    Map<String, dynamic> data, {
    required String company,
    required String family,
    required String field,
    required int start,
  }) {
    if (data['version'] != 1 ||
        data['company'] != company ||
        data['family'] != family ||
        data['field'] != field ||
        data['start'] != start ||
        data['has_more'] is! bool ||
        data['rows'] is! List) {
      throw const ErpException(
        'The history choices returned an unexpected scope.',
      );
    }
    final items = List<Map<String, dynamic>>.from(
      (data['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)),
    );
    if (items.length > 50 ||
        items.any(
          (r) =>
              r['label'] is! String ||
              (r['label'] as String).isEmpty ||
              (r['label'] as String).length > 4096 ||
              (!r.containsKey('value')) ||
              (field == 'source_job' &&
                  (r['value'] is! String ||
                      (r['value'] as String).isEmpty ||
                      (r['value'] as String).length > 140)) ||
              (r['value'] is! String &&
                  !(r['value'] == null && field == 'source_book')),
        ) ||
        items.map((r) => r['value']).toSet().length != items.length) {
      throw const ErpException(
        'The history choices returned an unexpected format.',
      );
    }
    return HistoryChoicesPage._(data, start);
  }
}

class OriginalRecordData {
  OriginalRecordData._(Map<String, dynamic> value)
    : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  factory OriginalRecordData.fromJson(
    Map<String, dynamic> data, {
    required String company,
    required String name,
  }) {
    if (data['version'] != 1 ||
        data['company'] != company ||
        data['source_record'] != name ||
        data['source_copy'] != true) {
      throw const ErpException(
        'The original record returned an unexpected scope.',
      );
    }
    return OriginalRecordData.forRendering(data);
  }
  factory OriginalRecordData.forRendering(Map<String, dynamic> data) {
    if (data['version'] != 1 ||
        data['source_copy'] != true ||
        [
          'company',
          'source_record',
          'document_label',
          'title',
        ].any((key) => data[key] is! String || (data[key] as String).isEmpty)) {
      throw const FormatException(
        'This is not an authorized original record copy.',
      );
    }
    final fields = _printRows(data['fields']),
        tables = _printRows(data['tables']);
    bool scalar(Object? value) =>
        value == null || value is String || value is num || value is bool;
    if (fields.any((f) => f['label'] is! String || !scalar(f['value'])) ||
        data['review_notes'] is! List ||
        (data['review_notes'] as List).any((v) => v is! String)) {
      throw const FormatException(
        'The original record has invalid print fields.',
      );
    }
    for (final table in tables) {
      final columns = _printRows(table['columns']),
          rows = _printRows(table['rows']);
      if (table['title'] is! String ||
          columns.isEmpty && rows.any((row) => row.isNotEmpty) ||
          columns.any((c) => c['key'] is! String || c['label'] is! String) ||
          columns.map((c) => c['key']).toSet().length != columns.length ||
          rows.any((row) => columns.any((c) => !scalar(row[c['key']])))) {
        throw const FormatException(
          'The original record has an invalid source table.',
        );
      }
    }
    return OriginalRecordData._(data);
  }
}
