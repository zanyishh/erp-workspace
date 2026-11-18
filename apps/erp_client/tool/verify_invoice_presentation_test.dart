// Fresh synthetic invoice presentation checks. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/erp_invoice_repository.dart';
import 'package:erp_client/features/invoices/data/invoice_logo_service.dart';
import 'package:erp_client/features/invoices/models/invoice_print_data.dart';
import 'package:erp_client/features/invoices/presentation/invoice_preview_view.dart';
import 'package:erp_client/features/invoices/presentation/invoice_preview_view_model.dart';
import 'package:erp_client/features/invoices/presentation/invoice_settings_view_model.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'synthetic stationery, native and original PDFs preserve financial data',
    (t) async {
      final password = Platform.environment['ERP_PASSWORD'];
      final raw = Platform.environment['ERP_INVOICE_PRESENTATION_FIXTURE'];
      if (password == null || raw == null) {
        throw StateError('Require synthetic credentials and fixture.');
      }
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final companies = (fixture['companies'] as List).cast<String>();
      if (fixture['site'] != 'native-test.localhost' ||
          companies.length != 4 ||
          companies.any(
            (v) => !v.startsWith('Architecture Invoice Presentation '),
          )) {
        throw StateError('Refusing unrelated fixture material.');
      }
      final api = ErpApi(Uri.parse('http://127.0.0.1:8081'));
      addTearDown(api.close);
      final directory = Directory.systemTemp.createTempSync(
        'erp-presentation-connected-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final logo = File('${directory.path}/logo.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO9WKS8AAAAASUVORK5CYII=',
          ),
        );
      final exported = File('${directory.path}/invoice.pdf');
      var pickerOpened = false;
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        if (call.method == 'openFile') return [logo.path];
        if (call.method == 'getSavePath') {
          pickerOpened = true;
          return exported.path;
        }
        throw MissingPluginException();
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      await t.runAsync(() async {
        await api.login('Administrator', password);
        expect((await api.nativeCatalog()).site, 'native-test.localhost');
        await api.workspaceContext(company: companies.first);
        final repository = ErpInvoiceRepository(
          api: api,
          company: companies.first,
        );
        final settings = InvoiceSettingsViewModel(
          repository,
          pickLogo: const InvoiceLogoService().pick,
        );
        try {
          await settings.loaded;
          expect(settings.canManage, isTrue);
          for (final entry in {
            'bank_name': 'Synthetic Test Bank',
            'account_holder': 'Synthetic Holder',
            'account_number': '000000000001',
            'ifsc': 'TEST0000000',
            'upi_name': 'Synthetic Payee',
            'upi_id': 'synthetic@upi',
          }.entries) {
            settings.change(entry.key, entry.value);
          }
          expect(
            settings.acceptTemplateChoice(
              settings.prepareTemplateChoice()!,
              'canopy',
            ),
            isTrue,
          );
          await settings.chooseLogo();
          expect(settings.image, isNotNull);
          expect(await settings.save(), isTrue);
          final saved = await repository.settings();
          expect(saved.settings['bank_name'], 'Synthetic Test Bank');
          expect(saved.settings['template_id'], 'canopy');
          expect(saved.settings['logo_base64'], isNotEmpty);
          final other = await ErpInvoiceRepository(
            api: api,
            company: companies[1],
          ).settings();
          expect(other.settings['bank_name'], isEmpty);
          expect(other.settings['template_id'], 'ledger');
        } finally {
          settings.dispose();
        }
        InvoicePreviewViewModel preview(InvoicePreviewSource source) =>
            InvoicePreviewViewModel(
              repository,
              source: source,
              render: (style, data, paper) =>
                  buildInvoicePdf(style, data.data, paper: paper),
            );
        final sample = preview(const InvoicePreviewSource.sample());
        try {
          final data = await sample.data;
          expect(
            (data.data['settings'] as Map)['bank_name'],
            'Synthetic Test Bank',
          );
          expect(sample.selected.id, 'canopy');
          expect(
            (await sample.pdf!).filename,
            'Sample - ${sample.selected.name}.pdf',
          );
          expect(sample.canSaveStyle, isFalse);
        } finally {
          sample.dispose();
        }
        final native = preview(
          InvoicePreviewSource.native(fixture['invoice'] as String),
        );
        try {
          final data = await native.data;
          expect(data.data['docstatus'], 1);
          expect(num.parse(data.data['grand_total'].toString()), 12.5);
          expect(data.data['upi_uri'].toString(), contains('synthetic%40upi'));
          expect(
            String.fromCharCodes((await native.pdf!).bytes.take(5)),
            '%PDF-',
          );
          expect(
            native.selectTemplate(
              native.prepareSelection()!,
              invoiceTemplateById('folio'),
            ),
            isTrue,
          );
          expect(await native.saveStyle(), isTrue);
          expect(native.savedOverride, 'folio');
          expect(
            (await repository.settings()).settings['template_id'],
            'canopy',
          );
          expect(await native.saveStyle(inherit: true), isTrue);
          expect(native.savedOverride, isEmpty);
          expect(native.selected.id, 'canopy');
          await native.pdf;
        } finally {
          native.dispose();
        }
        final original = preview(
          InvoicePreviewSource.original(fixture['original'] as String),
        );
        try {
          final data = await original.data;
          expect(data.data['source_reference'], fixture['originalReference']);
          expect(data.data['source_copy'], isTrue);
          expect(data.data['settings'], isEmpty);
          expect(data.data['upi_uri'], isNull);
          expect(original.canSaveStyle, isFalse);
          expect(original.canInherit, isFalse);
          expect(
            original.selectTemplate(
              original.prepareSelection()!,
              invoiceTemplateById('folio'),
            ),
            isTrue,
          );
          expect(await original.saveStyle(), isFalse);
          expect(
            String.fromCharCodes((await original.pdf!).bytes.take(5)),
            '%PDF-',
          );
        } finally {
          original.dispose();
        }
      });
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 800);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: InvoicePreviewScreen(
            api: api,
            company: companies.first,
            invoice: fixture['invoice'] as String,
          ),
        ),
      );
      Future<void> wait(bool Function() ready) async {
        for (var i = 0; i < 240; i++) {
          await t.pump(const Duration(milliseconds: 30));
          if (ready()) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        fail('Connected invoice preview did not reach the expected state.');
      }

      await wait(() => find.text('Export PDF').evaluate().isNotEmpty);
      await t.tap(find.text('Export PDF'));
      await wait(
        () =>
            exported.existsSync() &&
            exported.lengthSync() > 5 &&
            !t
                .widget<InvoicePreviewView>(find.byType(InvoicePreviewView))
                .model
                .working,
      );
      expect(pickerOpened, isTrue);
      expect(String.fromCharCodes(exported.readAsBytesSync().take(5)), '%PDF-');
      final bytes = exported.readAsBytesSync();
      expect(
        String.fromCharCodes(bytes.skip(bytes.length - 32)),
        contains('%%EOF'),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(api.signOut);
      api.close();
      await t.pump(const Duration(seconds: 30));
      stdout.writeln(
        jsonEncode({
          'site': fixture['site'],
          'settingsAndLogo': 'passed',
          'secondCompanyIsolation': 'passed',
          'samplePdf': 'passed',
          'postedNativePdf': 'passed',
          'styleOverrideAndInheritance': 'passed',
          'immutableOriginalCopy': 'passed',
          'reauthorizedPdfFileExport': 'passed',
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
