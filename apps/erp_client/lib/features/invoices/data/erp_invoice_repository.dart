import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import '../../../erp_api.dart' show ErpApi;
import 'invoice_repository.dart';
import 'invoice_composer_repository.dart';
import '../models/invoice_compose.dart';
import '../models/invoice_profile.dart';
import '../models/invoice_print_data.dart';
import '../models/sample_invoice_data.dart';

class ErpInvoiceRepository
    implements
        InvoiceRegisterRepository,
        InvoiceSettingsRepository,
        InvoicePreviewRepository,
        InvoiceComposerRepository {
  ErpInvoiceRepository({required this._api, required this.company});
  final ErpApi _api;
  @override
  final String company;
  @override
  Object get identity => (_api, _api.baseUri, _api.account, company);
  @override
  Object? get scope =>
      _api.accessReady ? (identity, _api.accessRevision) : null;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  @override
  Future<InvoiceRegisterPage> register({
    String query = '',
    String status = 'All',
    int start = 0,
    int pageSize = 25,
  }) async {
    final captured = scope;
    if (captured == null) throw _changed;
    final value = await _api.salesInvoices(
      company,
      query: query,
      status: status,
      start: start,
      limit: pageSize,
    );
    if (captured != scope) throw _changed;
    return InvoiceRegisterPage.fromJson(
      value,
      company: company,
      pageSize: pageSize,
    );
  }

  @override
  Future<InvoiceProfile> settings() async {
    final captured = scope;
    if (captured == null) throw _changed;
    final value = await _api.invoiceSettings(company);
    if (captured != scope) throw _changed;
    return InvoiceProfile.fromJson(value, company: company);
  }

  @override
  Future<InvoiceProfile> saveSettings(
    Map<String, String> values,
    String revision,
  ) async {
    if (scope == null) throw _changed;
    final snapshot = Map<String, String>.unmodifiable(Map.of(values));
    final value = await _api.saveInvoiceSettings(company, snapshot, revision);
    // A completed mutation may have committed; the model reconciles its scope.
    return InvoiceProfile.fromJson(value, company: company);
  }

  @override
  Future<InvoicePrintData> source(InvoicePreviewSource source) async {
    final captured = scope;
    if (captured == null) throw _changed;
    final Map<String, dynamic> value;
    switch (source.kind) {
      case InvoiceSourceKind.native:
        value = await _api.invoicePrintData(company, source.name);
      case InvoiceSourceKind.original:
        value = await _api.importedInvoicePrintData(company, source.name);
      case InvoiceSourceKind.sample:
        final profile = await settings();
        value = {
          ...sampleInvoiceData(),
          'name': 'SAMPLE-0048',
          'company': company,
          'seller_name': company,
          'company_address': '',
          'template_id': profile.settings['template_id'],
          'settings': profile.settings,
        };
    }
    if (captured != scope) throw _changed;
    return InvoicePrintData.fromJson(value, company: company, source: source);
  }

  @override
  Future<void> saveTemplate(String invoice, String templateId) async {
    if (scope == null) throw _changed;
    await _api.setInvoiceTemplate(company, invoice, templateId);
  }

  @override
  bool get supportsRecovery => _api.supportsOperationRecovery(company);
  Object _capture() => scope ?? (throw _changed);
  void _require(Object captured) {
    if (scope != captured) throw _changed;
  }

  @override
  Future<InvoiceComposeDefaults> defaults() async {
    final captured = _capture();
    final value = await _api.invoiceDefaults(company);
    _require(captured);
    return InvoiceComposeDefaults.fromJson(value);
  }

  @override
  Future<InvoiceReview> review(Map<String, Object?> draft) async {
    final captured = _capture(), snapshot = immutableJsonMap(draft);
    if (snapshot['company'] != company) throw _changed;
    final value = await _api.reviewInvoice(snapshot);
    _require(captured);
    return InvoiceReview.fromJson(
      value,
      company: company,
      itemCount: (snapshot['items'] as List).length,
    );
  }

  @override
  Future<String> save(
    Map<String, Object?> draft,
    String requestId,
    String review,
  ) {
    _capture();
    final snapshot = immutableJsonMap(draft);
    if (snapshot['company'] != company) throw _changed;
    return _api.saveInvoiceDraft(snapshot, requestId, review);
  }

  @override
  Future<InvoiceSaveStatus> prepare(String requestId) async {
    _capture();
    final value = await _api.beginOperation(company, 'invoice', requestId);
    return InvoiceSaveStatus.fromJson(
      value,
      company: company,
      requestId: requestId,
    );
  }

  @override
  Future<InvoiceSaveStatus> status(
    String requestId, {
    bool close = false,
  }) async {
    final captured = _capture();
    final value = close
        ? await _api.closeOperation(company, requestId)
        : await _api.operationStatus(company, requestId);
    _require(captured);
    return InvoiceSaveStatus.fromJson(
      value,
      company: company,
      requestId: requestId,
    );
  }

  @override
  Future<void> acknowledge(String requestId) {
    _capture();
    return _api.acknowledgeOperation(company, requestId);
  }

  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query,
  ) async {
    final captured = _capture();
    final rows = await _api.searchLinks(
      doctype,
      query,
      parent: 'Sales Invoice',
      field: doctype == 'Item' ? 'item_code' : 'customer',
      contextValues: {'company': company},
    );
    _require(captured);
    return List.unmodifiable(rows.map(immutableJsonMap));
  }

  @override
  Future<void> setTemplate(String name, String templateId) =>
      saveTemplate(name, templateId);
}
