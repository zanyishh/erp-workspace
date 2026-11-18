import '../models/invoice_compose.dart';

abstract class InvoiceComposerRepository {
  Object get identity;
  Object? get scope;
  String get company;
  bool get supportsRecovery;
  Future<InvoiceComposeDefaults> defaults();
  Future<InvoiceReview> review(Map<String, Object?> draft);
  Future<String> save(
    Map<String, Object?> draft,
    String requestId,
    String review,
  );
  Future<InvoiceSaveStatus> prepare(String requestId);
  Future<InvoiceSaveStatus> status(String requestId, {bool close = false});
  Future<void> acknowledge(String requestId);
  Future<List<Map<String, dynamic>>> searchLinks(String doctype, String query);
  Future<void> setTemplate(String name, String templateId);
}
