import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';

enum InvoiceSourceKind { native, original, sample }

class InvoicePreviewSource {
  const InvoicePreviewSource.native(this.name, {this.draftRevision})
    : kind = InvoiceSourceKind.native;
  const InvoicePreviewSource.original(this.name)
    : draftRevision = null,
      kind = InvoiceSourceKind.original;
  const InvoicePreviewSource.sample()
    : draftRevision = null,
      kind = InvoiceSourceKind.sample,
      name = '';
  final InvoiceSourceKind kind;
  final String name;
  final String? draftRevision;
}

class InvoicePrintData {
  InvoicePrintData._(Map<String, dynamic> value)
    : data = immutableJsonMap(value);
  final Map<String, dynamic> data;
  bool get canSetTemplate => data['can_set_template'] == true;
  String get templateId => data['template_id']?.toString() ?? 'ledger';
  String get templateOverride => data['template_override']?.toString() ?? '';
  factory InvoicePrintData.fromJson(
    Map<String, dynamic> value, {
    required String company,
    required InvoicePreviewSource source,
  }) {
    if (value['company'] != company ||
        value['name'] is! String ||
        (value['name'] as String).isEmpty ||
        source.kind == InvoiceSourceKind.native &&
            value['name'] != source.name ||
        source.kind == InvoiceSourceKind.original &&
            (value['source_record'] != source.name ||
                value['source_copy'] != true) ||
        value['can_set_template'] != null &&
            value['can_set_template'] is! bool ||
        [
          'template_id',
          'template_override',
        ].any((key) => value[key] != null && value[key] is! String)) {
      throw const ErpException(
        'The invoice returned an unexpected scope or format. Refresh and try again.',
      );
    }
    if (source.draftRevision != null &&
        (value['modified'] != source.draftRevision ||
            value['docstatus'] != 0)) {
      throw const ErpException(
        'This draft has changed. Return to the editor and reload it before submitting.',
        staleDocument: true,
      );
    }
    return InvoicePrintData._(value);
  }
}
