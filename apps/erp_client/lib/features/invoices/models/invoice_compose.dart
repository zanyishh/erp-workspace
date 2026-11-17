import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';

const _invalid = ErpException(
  'The invoice returned an unexpected scope or format. Refresh and try again.',
);
final _decimalParts = RegExp(
  r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$',
);

String? invoiceNumberError(String value, {bool positive = false}) {
  final parts = _decimalParts.firstMatch(value.trim());
  final signError = positive
      ? 'Enter a positive quantity.'
      : 'Enter zero or a positive rate.';
  if (parts == null) return signError;
  final fraction = parts[3] ?? '';
  final digits = parts[2]! + fraction;
  if (digits.isEmpty) return signError;
  final significant = digits.replaceFirst(RegExp(r'^0+'), '');
  if (significant.isEmpty ? positive : parts[1] == '-') return signError;
  // Compare decimal positions directly so a value just below the server limit
  // is not rounded up by a binary floating-point conversion.
  final exponent = int.tryParse(parts[4] ?? '0');
  if (exponent == null) return 'Enter a smaller exponent.';
  if (exponent < fraction.length - 9) return 'Use up to 9 decimal places.';
  if (significant.isNotEmpty &&
      exponent >= 13 + fraction.length - significant.length) {
    return 'Enter a value below 10 trillion.';
  }
  return null;
}

bool validInvoiceNumber(String value, {bool positive = false}) =>
    invoiceNumberError(value, positive: positive) == null;

class InvoiceDraftLine {
  InvoiceDraftLine({Object? id, this.item = '', this.qty = '1', this.rate = ''})
    : id = id ?? Object();
  final Object id;
  final String item, qty, rate;
  InvoiceDraftLine copyWith({String? item, String? qty, String? rate}) =>
      InvoiceDraftLine(
        id: id,
        item: item ?? this.item,
        qty: qty ?? this.qty,
        rate: rate ?? this.rate,
      );
  Map<String, Object?> get values => Map.unmodifiable({
    'item_code': item.trim(),
    'qty': qty.trim(),
    if (rate.trim().isNotEmpty) 'rate': rate.trim(),
  });
  bool get valid =>
      item.trim().isNotEmpty &&
      validInvoiceNumber(qty, positive: true) &&
      (rate.trim().isEmpty || validInvoiceNumber(rate));
}

class InvoiceComposeDefaults {
  const InvoiceComposeDefaults._(this.postingDate, this.templateId);
  factory InvoiceComposeDefaults.fromJson(Map<String, dynamic> value) {
    final date = value['posting_date'], style = value['template_id'];
    if (date is! String ||
        DateTime.tryParse(date) == null ||
        style != null && style is! String) {
      throw _invalid;
    }
    return InvoiceComposeDefaults._(date, style as String? ?? 'ledger');
  }
  final String postingDate, templateId;
}

class InvoiceReview {
  InvoiceReview._(Map<String, dynamic> value) : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  String get token => data['review'] as String;
  List<(String, Object?)> get summaryTotals => [
    ('Net amount', data['net_total']),
    for (final tax in (data['taxes'] as List).cast<Map>())
      (tax['label'] as String, tax['amount']),
    if (double.tryParse(data['rounding_adjustment']?.toString() ?? '0') != 0)
      ('Rounding', data['rounding_adjustment']),
    (
      'Total',
      data['disable_rounded_total'] == true ||
              double.tryParse(data['rounded_total']?.toString() ?? '0') == 0
          ? data['grand_total']
          : data['rounded_total'],
    ),
  ];
  factory InvoiceReview.fromJson(
    Map<String, dynamic> value, {
    required String company,
    required int itemCount,
  }) {
    final items = value['items'],
        taxes = value['taxes'],
        precision = value['precision'];
    bool amount(Object? v) =>
        v != null && num.tryParse(v.toString())?.isFinite == true;
    if (value['company'] != null && value['company'] != company ||
        value['review'] is! String ||
        (value['review'] as String).isEmpty ||
        value['currency'] is! String ||
        (value['currency'] as String).isEmpty ||
        precision is! int ||
        precision < 0 ||
        precision > 10 ||
        !amount(value['net_total']) ||
        !amount(value['grand_total']) ||
        items is! List ||
        items.length != itemCount ||
        items.any(
          (r) =>
              r is! Map ||
              !['qty', 'rate', 'amount'].every((k) => amount(r[k])),
        ) ||
        taxes is! List ||
        taxes.any(
          (r) => r is! Map || r['label'] is! String || !amount(r['amount']),
        )) {
      throw _invalid;
    }
    return InvoiceReview._(value);
  }
}

class InvoiceSaveStatus {
  const InvoiceSaveStatus._(this.state, this.name);
  factory InvoiceSaveStatus.fromJson(
    Map<String, dynamic> value, {
    required String company,
    required String requestId,
  }) {
    final state = value['state'], result = value['result'];
    final name = result is Map ? result['name'] : null;
    if (value['company'] != null && value['company'] != company ||
        value['request_id'] != null && value['request_id'] != requestId ||
        !['prepared', 'completed', 'closed'].contains(state) ||
        state == 'completed' && (name is! String || name.isEmpty)) {
      throw _invalid;
    }
    return InvoiceSaveStatus._(state as String, name as String?);
  }
  final String state;
  final String? name;
}

enum InvoiceLeaveState { free, discard, pending, blocked, busy }
