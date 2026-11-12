import 'native_models.dart';

String plainReportText(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

class NativeReportColumn {
  NativeReportColumn.fromJson(Object? value) {
    if (value is String) {
      final parts = value.split(':');
      label = parts.first;
      fieldname = label.toLowerCase().replaceAll(' ', '_');
      final kind = parts.length > 1 ? parts[1].split('/') : ['Data'];
      type = kind.first;
      options = kind.length > 1 ? kind[1] : '';
    } else {
      final map = objectMap(value);
      label = map['label']?.toString() ?? '';
      fieldname =
          map['fieldname']?.toString() ??
          label.toLowerCase().replaceAll(' ', '_');
      type = map['fieldtype']?.toString() ?? 'Data';
      options = map['options']?.toString() ?? '';
    }
  }
  late final String fieldname, label, type, options;
}

class NativeReportResult {
  NativeReportResult.fromJson(Map<String, dynamic> json)
    : columns = (json['columns'] as List? ?? [])
          .map(NativeReportColumn.fromJson)
          .toList(),
      pending = enabled(json['prepared_report']) && json['result'] == null,
      truncated = enabled(json['truncated']),
      summary = (json['report_summary'] as List? ?? [])
          .map(objectMap)
          .toList() {
    if (json['error'] is String && (json['error'] as String).isNotEmpty) {
      throw FormatException(plainReportText(json['error']));
    }
    for (final raw in json['result'] as List? ?? []) {
      if (raw is List) {
        rows.add({
          for (var i = 0; i < columns.length; i++)
            columns[i].fieldname: i < raw.length ? raw[i] : null,
        });
      } else {
        rows.add(objectMap(raw));
      }
    }
  }
  final List<NativeReportColumn> columns;
  final List<Map<String, dynamic>> rows = [];
  final List<Map<String, dynamic>> summary;
  final bool pending, truncated;

  String csv() {
    String cell(Object? value) {
      if (value is num) return value.toString();
      var text = plainReportText(value);
      if (RegExp(r'^[=+\-@\t\r]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    return '${[columns.map((c) => cell(c.label)).join(','), for (final row in rows) columns.map((c) => cell(row[c.fieldname])).join(',')].join('\r\n')}\r\n';
  }
}
