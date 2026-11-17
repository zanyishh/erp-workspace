import '../models/invoice_print_data.dart';
import '../models/invoice_profile.dart';
import '../models/invoice_register_page.dart';
export '../models/invoice_register_page.dart';

abstract class InvoiceRegisterRepository {
  Object get identity;
  Object? get scope;
  Future<InvoiceRegisterPage> register({
    String query = '',
    String status = 'All',
    int start = 0,
    int pageSize = 25,
  });
}

abstract class InvoiceSettingsRepository {
  Object get identity;
  Object? get scope;
  Future<InvoiceProfile> settings();
  Future<InvoiceProfile> saveSettings(
    Map<String, String> values,
    String revision,
  );
}

abstract class InvoicePreviewRepository {
  Object get identity;
  Object? get scope;
  Future<InvoicePrintData> source(InvoicePreviewSource source);
  Future<void> saveTemplate(String invoice, String templateId);
}
