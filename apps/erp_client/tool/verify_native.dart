import 'dart:convert';
import 'dart:io';
import 'package:erp_client/erp_api.dart';

Future<void> main() async {
  final url = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://localhost:8081',
  );
  if (!['localhost', '127.0.0.1'].contains(url.host) || url.port != 8081) {
    throw StateError(
      'Native write verification requires the isolated localhost:8081 test site.',
    );
  }
  final user = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (user == null || password == null) {
    throw StateError(
      'Set verification account credentials in the process environment.',
    );
  }
  final api = ErpApi(url);
  try {
    await api.login(user, password);
    final catalog = await api.nativeCatalog();
    if (catalog.site != 'native-test.localhost') {
      throw StateError(
        'Refusing to write outside the dedicated native test site.',
      );
    }
    const type = 'Native Workspace Test Record';
    final schema = await api.nativeSchema(type);
    final draft = await api.nativeDocument(type);
    final values = draft.editCopy()
      ..['title'] = 'Native verification ${DateTime.now().toIso8601String()}'
      ..['amount'] = 12.5;
    final row = await api.newRowNative(schema, values, 'rows');
    row['description'] = 'Created through the Dart native contract';
    values['rows'] = [row];
    final saved = await api.saveNative(schema, values);
    final edited = saved.editCopy()
      ..['title'] = 'Edited through Flutter contract';
    final updated = await api.saveNative(schema, edited);
    final reopened = await api.nativeDocument(
      type,
      name: updated.data['name'] as String,
    );
    if (reopened.data['title'] != 'Edited through Flutter contract' ||
        reopened.data['amount'] != 12.5 ||
        (reopened.data['rows'] as List).single['description'] !=
            'Created through the Dart native contract') {
      throw StateError('Reopened document differs from the native edit.');
    }
    final name = reopened.data['name'] as String;
    await api.comment(type, name, 'Native client verification comment');
    final raw = base64Decode('77u/TmF0aXZlIHByb29m');
    await api.uploadAttachment(type, name, 'native-verification.txt', raw);
    final activity = await api.documentActivity(type, name);
    final attachment = (activity['attachments'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => f['file_name'] == 'native-verification.txt');
    final downloaded = await api.attachment(
      type,
      name,
      attachment['name'] as String,
    );
    if (base64Encode(downloaded.bytes) != base64Encode(raw)) {
      throw StateError('Attachment bytes changed during transfer.');
    }
    await api.removeAttachment(type, name, attachment['name'] as String);
    final pdf = await api.printPdf(type, name, 'Standard');
    if (!ascii.decode(pdf.bytes.take(5).toList()).startsWith('%PDF-')) {
      throw StateError('Print did not return a PDF.');
    }
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'availableRecordTypes': catalog.types.length,
        'availableReports': catalog.reports.length,
        'document': reopened.data['name'],
        'createEditReopen': 'passed',
        'childRows': 'passed',
        'serverValidation': 'passed',
        'privateAttachmentExactBytes': 'passed',
        'commentsAndHistory': 'passed',
        'pdfPrint': 'passed',
      }),
    );
    await api.signOut();
  } finally {
    api.close();
  }
}
