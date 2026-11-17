import '../models/history_filter_values.dart';

String historyFilterValue(
  String field,
  Object? value,
  Map<String, String> labels,
) => field == 'source_job'
    ? labels[field] ?? 'Selected job'
    : '${value ?? 'No source book'}';

String historyFilterSummary(
  Map<String, dynamic> filters, {
  Map<String, String> labels = const {},
}) => filters.entries
    .map(
      (e) => e.key == 'date_basis'
          ? historyDateLabels[e.value] ?? e.value.toString()
          : '${historyFilterLabels[e.key] ?? (e.key == 'from_date' ? 'From' : 'Through')}: ${historyFilterValue(e.key, e.value, labels)}',
    )
    .join(' · ');
