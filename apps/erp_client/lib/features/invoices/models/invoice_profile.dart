import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';

const invoiceSettingFields = [
  'template_id',
  'accent_color',
  'signatory_name',
  'print_footer',
  'logo_base64',
  'bank_name',
  'account_holder',
  'account_number',
  'ifsc',
  'upi_id',
  'upi_name',
];

class InvoiceProfile {
  InvoiceProfile._(Map<String, dynamic> value) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  bool get canManage => data['can_manage'] == true;
  String get revision => data['revision']?.toString() ?? '';
  late final Map<String, String> settings = Map.unmodifiable({
    for (final e in (data['settings'] as Map).entries)
      e.key as String: e.value as String? ?? '',
  });
  factory InvoiceProfile.fromJson(
    Map<String, dynamic> value, {
    required String company,
  }) {
    final settings = value['settings'];
    if (value['company'] != company ||
        settings is! Map ||
        settings.entries.any(
          (e) => e.key is! String || e.value != null && e.value is! String,
        ) ||
        value['can_manage'] != null && value['can_manage'] is! bool) {
      throw const ErpException(
        'The invoice settings returned an unexpected scope or format. Refresh and try again.',
      );
    }
    return InvoiceProfile._(value);
  }
}
