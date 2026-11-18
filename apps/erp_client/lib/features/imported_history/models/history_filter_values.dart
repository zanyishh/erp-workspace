import '../../../core/models/erp_exception.dart';

const historyFilterLabels = {
  'source_book': 'Source book',
  'party': 'Original party name',
  'job': 'Original order value',
  'source_job': 'Job order',
  'status': 'Original status',
  'shift': 'Shift',
  'machine': 'Machine',
  'operator': 'Employee / operator',
  'description': 'Fabric',
  'dia': 'Dia / size',
};
const historyDateLabels = {
  '': 'All dates',
  'original': 'Original date',
  'effective': 'Effective date',
  'no_original': 'No original date',
};

Map<String, String> parseHistoryFilterLabels(
  Object? raw,
  Map<String, dynamic> filters,
) {
  if (raw == null) return {};
  if (raw is! Map ||
      raw.entries.any(
        (e) =>
            e.key != 'source_job' ||
            !filters.containsKey(e.key) ||
            e.value is! String ||
            (e.value as String).isEmpty ||
            (e.value as String).length > 4096 ||
            (e.value as String).contains('\u0000'),
      )) {
    throw const ErpException(
      'The history filter labels returned an unexpected format.',
    );
  }
  return Map<String, String>.from(raw);
}
