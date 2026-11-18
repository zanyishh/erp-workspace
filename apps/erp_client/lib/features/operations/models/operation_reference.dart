String? _text(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid operation field.');
  return value;
}

typedef OperationTarget = ({String doctype, String name});

class OperationReceipt {
  const OperationReceipt({
    this.name,
    this.event,
    this.payment,
    this.invoice,
    this.hasValues = false,
  });
  factory OperationReceipt.fromJson(Object? json) {
    if (json == null) return const OperationReceipt();
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid operation receipt.');
    }
    return OperationReceipt(
      name: _text(json['name']),
      event: _text(json['event']),
      payment: _text(json['payment']),
      invoice: _text(json['invoice']),
      hasValues: json.isNotEmpty,
    );
  }
  final String? name, event, payment, invoice;
  final bool hasValues;
}

class OperationReference {
  const OperationReference({
    required this.requestId,
    required this.company,
    required this.state,
    this.kind,
    this.action,
    this.doctype,
    this.name,
    this.creation = '',
    this.result = const OperationReceipt(),
  });
  factory OperationReference.fromJson(Map<String, dynamic> json) {
    final id = _text(json['request_id']),
        company = _text(json['company']),
        state = _text(json['state']);
    if (id == null ||
        id.isEmpty ||
        company == null ||
        company.isEmpty ||
        state == null ||
        state.isEmpty) {
      throw const FormatException('Invalid operation identity.');
    }
    return OperationReference(
      requestId: id,
      company: company,
      state: state,
      kind: _text(json['kind']),
      action: _text(json['action']),
      doctype: _text(json['doctype']),
      name: _text(json['name']),
      creation: _text(json['creation']) ?? '',
      result: OperationReceipt.fromJson(json['result']),
    );
  }
  final String requestId, company, state, creation;
  final String? kind, action, doctype, name;
  final OperationReceipt result;
  String? get savedName => name ?? result.name;
  OperationTarget? get target {
    final type = doctype ?? (kind == 'invoice' ? 'Sales Invoice' : null);
    final saved = savedName;
    return type == null || saved == null ? null : (doctype: type, name: saved);
  }
}

class OperationPage {
  OperationPage({
    required Iterable<OperationReference> rows,
    required this.hasMore,
  }) : rows = List.unmodifiable(rows);
  factory OperationPage.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    if (rows is! List || json['has_more'] is! bool) {
      throw const FormatException('Invalid operation page.');
    }
    return OperationPage(
      rows: rows.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid operation row.');
        }
        return OperationReference.fromJson(row);
      }),
      hasMore: json['has_more'] as bool,
    );
  }
  final List<OperationReference> rows;
  final bool hasMore;
}
