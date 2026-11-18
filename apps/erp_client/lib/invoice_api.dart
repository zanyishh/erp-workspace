part of 'erp_api.dart';

/// The native transport supplies the authenticated session and access-revision checks.
mixin _InvoiceApi {
  Future<Map<String, dynamic>> _industry(
    String module,
    String operation,
    Map<String, Object?> args,
  );

  Future<Map<String, dynamic>> invoiceDefaults(String company) =>
      _industry('invoice_compose', 'defaults', {'company': company});

  Future<Map<String, dynamic>> reviewInvoice(Map<String, Object?> draft) =>
      _industry('invoice_compose', 'preview', draft);

  Future<String> saveInvoiceDraft(
    Map<String, Object?> draft,
    String requestId,
    String review,
  ) async =>
      (await _industry('invoice_compose', 'save_draft', {
            ...draft,
            'request_id': requestId,
            'review': review,
          }))['name']
          as String;

  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) => _industry('invoices', 'register', {
    'company': company,
    'query': query,
    'status': status,
    'start': start,
    'limit': limit,
  });

  Future<Map<String, dynamic>> invoicePrintData(String company, String name) =>
      _industry('invoices', 'print_data', {'company': company, 'name': name});

  Future<Map<String, dynamic>> invoiceSettings(String company) =>
      _industry('invoices', 'get_settings', {'company': company});

  Future<Map<String, dynamic>> saveInvoiceSettings(
    String company,
    Map<String, String> settings,
    String revision,
  ) => _industry('invoices', 'save_settings', {
    'company': company,
    'settings': settings,
    'revision': revision,
  });

  Future<void> setInvoiceTemplate(
    String company,
    String name,
    String templateId,
  ) async {
    await _industry('invoices', 'set_template', {
      'company': company,
      'name': name,
      'template_id': templateId,
    });
  }
}
