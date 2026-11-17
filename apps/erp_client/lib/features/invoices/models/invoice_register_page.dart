import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';

class InvoiceRegisterPage {
  InvoiceRegisterPage._(Map<String, dynamic> value)
    : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  late final List<Map<String, dynamic>> rows = List.unmodifiable(
    (data['rows'] as List).cast<Map<String, dynamic>>(),
  );
  bool get hasMore => data['has_more'] == true;
  bool get canCreate => data['can_create'] == true;
  bool get canManageSettings => data['can_manage_settings'] == true;
  List<String>? get statuses => (data['statuses'] as List?)?.cast<String>();
  factory InvoiceRegisterPage.fromJson(
    Map<String, dynamic> value, {
    required String company,
    required int pageSize,
  }) {
    final rows = value['rows'], statuses = value['statuses'];
    if ((value.containsKey('company') && value['company'] != company) ||
        rows is! List ||
        rows.length > pageSize ||
        rows.any(
          (row) =>
              row is! Map ||
              row['name'] is! String ||
              (row['name'] as String).isEmpty,
        ) ||
        rows.map((row) => row['name']).toSet().length != rows.length ||
        (statuses != null &&
            (statuses is! List || statuses.any((v) => v is! String))) ||
        [
          'has_more',
          'can_create',
          'can_manage_settings',
        ].any((key) => value[key] != null && value[key] is! bool) ||
        value['default_template_id'] != null &&
            value['default_template_id'] is! String) {
      throw const ErpException(
        'The invoice register returned an unexpected format. Refresh and try again.',
      );
    }
    return InvoiceRegisterPage._(value);
  }
}
