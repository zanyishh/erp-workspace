import '../../../core/models/native_models.dart';
import 'report_values.dart';

String plainReportText(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

class NativeReportColumn {
  NativeReportColumn.fromJson(Object? value) {
    hidden = value is Map && enabled(value['hidden']);
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
  late final bool hidden;
}

class NativeReportResult {
  NativeReportResult.fromJson(Map<String, dynamic> json)
    : pending = enabled(json['prepared_report']) && json['result'] == null,
      truncated = enabled(json['truncated']),
      chart = NativeReportChart.parse(json['chart']),
      summary = List.unmodifiable(
        (json['report_summary'] as List? ?? []).map(
          (value) => immutableReportMap(objectMap(value)),
        ),
      ) {
    if (json['error'] is String && (json['error'] as String).isNotEmpty) {
      throw FormatException(plainReportText(json['error']));
    }
    final parsedRows = <Map<String, dynamic>>[];
    final allColumns = (json['columns'] as List? ?? [])
        .map(NativeReportColumn.fromJson)
        .toList();
    columns = List.unmodifiable(allColumns.where((column) => !column.hidden));
    for (final raw in json['result'] as List? ?? []) {
      if (raw is List) {
        parsedRows.add({
          for (var i = 0; i < allColumns.length; i++)
            allColumns[i].fieldname: i < raw.length ? raw[i] : null,
        });
      } else {
        parsedRows.add(objectMap(raw));
      }
    }
    rows = List.unmodifiable(parsedRows.map(immutableReportMap));
  }
  late final List<NativeReportColumn> columns;
  late final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> summary;
  final bool pending, truncated;
  final NativeReportChart? chart;

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

/// The ordinary Frappe chart payload can arrive alongside rows or on its own.
class ReportChartSeries {
  const ReportChartSeries(this.name, this.kind, this.values);
  final String name, kind;
  final List<double?> values;
}

class NativeReportChart {
  NativeReportChart(
    this.title,
    this.kind,
    this.currency,
    List<String> labels,
    List<ReportChartSeries> series,
  ) : labels = List.unmodifiable(labels),
      series = List.unmodifiable(
        series.map(
          (value) => ReportChartSeries(
            value.name,
            value.kind,
            List.unmodifiable(value.values),
          ),
        ),
      );
  final String title, kind, currency;
  final List<String> labels;
  final List<ReportChartSeries> series;
  bool get distribution => const {'pie', 'donut', 'percentage'}.contains(kind);

  static NativeReportChart? parse(Object? raw) {
    if (raw is! Map || raw['data'] is! Map) return null;
    final data = raw['data'] as Map;
    final points = data['labels'];
    final datasets = data['datasets'];
    if (points is! List || points.isEmpty || datasets is! List) return null;
    final labels = points.map(plainReportText).toList();
    final kind = (raw['type'] ?? 'line').toString();
    if (!const {
      'bar',
      'line',
      'axis-mixed',
      'donut',
      'pie',
      'percentage',
    }.contains(kind)) {
      return null;
    }
    final aggregate = const {'donut', 'pie', 'percentage'}.contains(kind);
    final totals = List<double?>.filled(labels.length, null);
    final series = <ReportChartSeries>[];
    var hasValue = false;
    for (final entry in datasets) {
      if (entry is! Map || entry['values'] is! List) continue;
      final values = entry['values'] as List;
      final parsed = List<double?>.generate(labels.length, (i) {
        if (i >= values.length || values[i] == null) return null;
        final number = double.tryParse(values[i].toString());
        if (number == null || !number.isFinite) return null;
        hasValue = true;
        if (aggregate) totals[i] = (totals[i] ?? 0) + number;
        return number;
      });
      if (!aggregate) {
        final fallback = datasets.length == 1
            ? 'Value'
            : 'Series ${series.length + 1}';
        final name = plainReportText(entry['name']);
        series.add(
          ReportChartSeries(
            name.isEmpty ? fallback : name,
            kind == 'axis-mixed'
                ? entry['chartType']?.toString() ?? 'bar'
                : kind,
            parsed,
          ),
        );
      }
    }
    if (!hasValue) return null;
    if (aggregate) {
      // Frappe sums the datasets by label and excludes negative slice totals.
      final keep = [
        for (var i = 0; i < totals.length; i++)
          if ((totals[i] ?? -1) >= 0) i,
      ];
      if (keep.isEmpty) return null;
      series.add(
        ReportChartSeries('Total', kind, [for (final i in keep) totals[i]]),
      );
      return NativeReportChart(
        plainReportText(raw['title']),
        kind,
        plainReportText(raw['currency']),
        [for (final i in keep) labels[i]],
        series,
      );
    }
    return NativeReportChart(
      plainReportText(raw['title']),
      kind,
      plainReportText(raw['currency']),
      labels,
      series,
    );
  }
}
