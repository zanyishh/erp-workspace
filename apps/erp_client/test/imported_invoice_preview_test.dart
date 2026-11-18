import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class OriginalInvoiceApi extends ErpApi {
  OriginalInvoiceApi() : super(Uri.parse('http://127.0.0.1:8082'));
  bool denied = false, wrongScope = false;
  int reads = 0, edits = 0;
  @override
  Future<Map<String, dynamic>> importedInvoicePrintData(
    String company,
    String name,
  ) async {
    reads++;
    if (denied) {
      throw const ErpException(
        'Original invoice access was revoked.',
        permissionDenied: true,
      );
    }
    return {
      ...sampleInvoiceData(),
      'company': company,
      'source_record': wrongScope ? 'other-record' : name,
      'source_copy': true,
      'source_reference': 'Original INV-48',
      'can_set_template': true,
      'template_override': 'ledger',
    };
  }

  @override
  Future<void> setInvoiceTemplate(
    String company,
    String name,
    String templateId,
  ) async {
    edits++;
  }
}

void main() {
  testWidgets(
    'compact preview keeps the paper visible and exposes print in the action menu',
    (t) async {
      final api = OriginalInvoiceApi();
      addTearDown(api.close);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 440);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: InvoicePreviewScreen(
            api: api,
            company: 'Archive One',
            importedRecord: 'history-invoice-48',
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      final export = find.byTooltip('Export PDF');
      expect(export.hitTestable(), findsOneWidget);
      expect(t.getBottomLeft(export).dy, lessThan(180));
      await t.tap(find.byTooltip('More invoice actions'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Print').hitTestable(), findsOneWidget);
      expect(find.text('Save template'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'original invoice opens from its immutable identity without a display-name argument',
    (t) async {
      final api = OriginalInvoiceApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoicePreviewScreen(
            api: api,
            company: 'Archive One',
            importedRecord: 'history-invoice-48',
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Original invoice'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'original PDF has no save action and rechecks permission before export',
    (t) async {
      final api = OriginalInvoiceApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: InvoicePreviewScreen(
            api: api,
            company: 'Archive One',
            invoice: 'Original INV-48',
            importedRecord: 'history-invoice-48',
          ),
        ),
      );
      // The native PDF rasterizer is outside this widget test. The permission
      // controls are available as soon as the authenticated source load completes.
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Use company default'), findsNothing);
      expect(find.text('Save template'), findsNothing);
      expect(find.text('Export PDF'), findsOneWidget);
      api.denied = true;
      await t.tap(find.text('Export PDF'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(api.reads, 2);
      expect(api.edits, 0);
      expect(find.text('Original invoice access was revoked.'), findsOneWidget);
    },
  );

  testWidgets('wrong original invoice scope never exposes PDF export', (
    t,
  ) async {
    final api = OriginalInvoiceApi()..wrongScope = true;
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: InvoicePreviewScreen(
          api: api,
          company: 'Archive One',
          invoice: 'Original INV-48',
          importedRecord: 'history-invoice-48',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Export PDF'), findsNothing);
    expect(find.textContaining('unexpected scope'), findsOneWidget);
  });
}
