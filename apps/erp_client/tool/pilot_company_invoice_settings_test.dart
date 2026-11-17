// Connected rehearsal. File dialogs supply a synthetic logo and every business call
// goes to this Mac's isolated company. Restore the original profile after the check.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:erp_client/invoice_settings.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'save General company branding once, keep Knitting branding separate, and restore it on company return',
    (t) async {
      expect(LocalWorkspace.enabled, isTrue);
      final support =
          "${Platform.environment['HOME']}/Library/Containers/org.localerp.erpClient/Data/Library/Application Support";
      const local = MethodChannel('org.localerp.workspace/local');
      const files = MethodChannel('plugins.flutter.io/file_selector');
      final fixture = File('test/fixtures/demo-invoice-logo.png').absolute;
      final messenger = t.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        local,
        (call) async => call.method == 'applicationSupport' ? support : null,
      );
      messenger.setMockMethodCallHandler(files, (call) async {
        expect(call.method, 'openFile');
        return [fixture.path];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(local, null);
        messenger.setMockMethodCallHandler(files, null);
      });
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1260, 1000);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final output = Platform.environment['INVOICE_PILOT_DIR'];
      Future<void> wait(Finder f) async {
        for (var i = 0; i < 240; i++) {
          await t.pump(const Duration(milliseconds: 80));
          if (f.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
        }
        fail('Could not open $f.');
      }

      Future<void> tap(Finder f) async {
        await wait(f);
        await t.ensureVisible(f.first);
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 400));
      }

      Future<void> snapshot(String name) async {
        if (output == null) return;
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> enter(String label, String value) async {
        final f = find.widgetWithText(TextFormField, label);
        await wait(f);
        await t.ensureVisible(f.first);
        await t.enterText(f.first, value);
      }

      String fieldValue(String label) => t
          .widget<TextFormField>(find.widgetWithText(TextFormField, label))
          .controller!
          .text;

      Future<void> leaveInvoices() async {
        await t.pump(const Duration(milliseconds: 500));
        if (find.byType(InvoiceSettingsScreen).evaluate().isNotEmpty) {
          await tap(
            find.descendant(
              of: find.byType(InvoiceSettingsScreen),
              matching: find.byType(BackButton),
            ),
          );
          await t.pump(const Duration(milliseconds: 400));
        }
        await tap(
          find.descendant(
            of: find.byType(InvoiceHub),
            matching: find.byType(BackButton),
          ),
        );
      }

      Future<void> selectCompany(String current, String next) async {
        await tap(find.text(current));
        await tap(find.widgetWithText(SimpleDialogOption, next));
      }

      for (final font in {
        'Manrope': 'assets/fonts/Manrope-Regular.ttf',
        'BarlowCondensed': 'assets/fonts/BarlowCondensed-SemiBold.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      await t.pumpWidget(
        RepaintBoundary(key: boundary, child: const ErpWorkspaceApp()),
      );
      await tap(find.text('Invoices'));
      await wait(find.byTooltip('Invoice settings'));
      final hub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
      final company = hub.company;
      expect(company, 'Meridian Trading');
      expect(hub.api.account, 'local-general-owner@workspace.example.invalid');
      // Keep an independent connection for cleanup when the shell swaps accounts.
      final owner = (await t.runAsync(
        () => LocalWorkspace.open(company: company),
      ))!;
      final api = owner.api;
      addTearDown(api.close);
      final knittingOwner = (await t.runAsync(
        () => LocalWorkspace.open(company: 'Kaveri Loomworks'),
      ))!;
      addTearDown(knittingOwner.api.close);
      final knittingBaseline = (await t.runAsync(
        () => knittingOwner.api.invoiceSettings('Kaveri Loomworks'),
      ))!;
      final knittingOriginal = Map<String, String>.from(
        knittingBaseline['settings'] as Map,
      );
      final baseline = (await t.runAsync(() => api.invoiceSettings(company)))!;
      final original = Map<String, String>.from(baseline['settings'] as Map);
      final choice = invoiceTemplateById(
        original['template_id'] == 'ribbon' ? 'cobalt' : 'ribbon',
      );
      String? restoreRevision;
      try {
        await tap(find.byTooltip('Invoice settings'));
        await tap(find.byTooltip('Choose default template'));
        await tap(find.text(choice.name).last);
        await tap(
          find.text(
            original['logo_base64']!.isEmpty ? 'Add logo' : 'Replace logo',
          ),
        );
        await wait(find.text('Replace logo'));
        await enter('Bank name', 'Example Bank');
        await enter('Account holder', 'Meridian Trading');
        await enter('Account number', '000012345678');
        await enter('IFSC', 'TEST0000001');
        await enter('UPI ID', 'demo-invoices@example');
        await enter('UPI payee name', 'Meridian Trading');
        await tap(find.text('Save settings'));
        await wait(find.text('Invoice settings saved for $company.'));
        final actual = (await t.runAsync(() => api.invoiceSettings(company)))!;
        restoreRevision = actual['revision'] as String;
        final settings = Map<String, String>.from(actual['settings'] as Map);
        expect(settings['logo_base64'], isNotEmpty);
        expect(base64Decode(settings['logo_base64']!).take(4), [
          137,
          80,
          78,
          71,
        ]);
        expect(settings['template_id'], choice.id);
        expect(settings['account_number'], '000012345678');
        final rows = (await t.runAsync(() => api.salesInvoices(company)))!;
        final bills = (rows['rows'] as List).cast<Map>().where(
          (r) => r['can_print'] == true && r['docstatus'] == 1,
        );
        Map<String, dynamic>? inherited;
        for (final bill in bills) {
          final data = (await t.runAsync(
            () => api.invoicePrintData(company, bill['name'] as String),
          ))!;
          if (data['template_override'] == '') {
            inherited = data;
            break;
          }
        }
        expect(
          inherited,
          isNotNull,
          reason: 'The local fixture must have a posted invoice inheriting its company style.',
        );
        final bill = inherited!;
        expect(bill['company'], 'Meridian Trading');
        expect(bill['template_id'], choice.id);
        expect(bill['settings'], settings);
        final payment = Uri.parse(bill['upi_uri'] as String);
        expect(payment.scheme, 'upi');
        expect(payment.host, 'pay');
        expect(payment.queryParameters['pa'], settings['upi_id']);
        expect(
          payment.queryParameters['am'],
          double.parse(bill['outstanding_amount'].toString())
              .toStringAsFixed(2),
        );
        final bytes = (await t.runAsync(() => buildInvoicePdf(choice, bill)))!;
        if (output != null) {
          await t.runAsync(
            () => File('$output/inherited-invoice.pdf').writeAsBytes(bytes),
          );
        }
        await leaveInvoices();
        await wait(find.byType(OverviewScreen));
        expect(find.text('Knitting workspace'), findsNothing);
        await selectCompany('Meridian Trading', 'Kaveri Loomworks');
        await wait(find.byType(KnittingScreen));
        await tap(find.text('Invoices'));
        await wait(find.byType(InvoiceHub));
        final millHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
        expect(millHub.company, 'Kaveri Loomworks');
        expect(millHub.api.account, 'local-owner@workspace.example.invalid');
        final knittingAfter = (await t.runAsync(
          () => millHub.api.invoiceSettings('Kaveri Loomworks'),
        ))!;
        expect(knittingAfter['settings'], knittingOriginal);
        expect(knittingAfter['revision'], knittingBaseline['revision']);
        await tap(find.byTooltip('Invoice settings'));
        await wait(find.widgetWithText(TextFormField, 'Account number'));
        await wait(
          find.text(invoiceTemplateById(knittingOriginal['template_id']!).name),
        );
        expect(
          fieldValue('Account number'),
          knittingOriginal['account_number'],
        );
        expect(
          fieldValue('Account holder'),
          knittingOriginal['account_holder'],
        );
        await snapshot('knitting-company-settings');
        await leaveInvoices();
        await wait(find.byType(KnittingScreen));
        await tap(find.text('General ERP'));
        await wait(find.byType(OverviewScreen));
        expect(
          t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
          'Kaveri Loomworks',
        );
        await tap(find.text('Invoices'));
        await wait(find.byType(InvoiceHub));
        final sharedHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
        expect(sharedHub.company, 'Kaveri Loomworks');
        expect(
          (await t.runAsync(
            () => sharedHub.api.invoiceSettings(sharedHub.company),
          ))!['settings'],
          knittingOriginal,
        );
        await leaveInvoices();
        await wait(find.byType(OverviewScreen));
        await selectCompany('Kaveri Loomworks', 'Meridian Trading');
        await wait(find.byType(OverviewScreen));
        await tap(find.text('Invoices'));
        await wait(find.byType(InvoiceHub));
        expect(
          t.widget<InvoiceHub>(find.byType(InvoiceHub)).company,
          'Meridian Trading',
        );
        await tap(find.byTooltip('Invoice settings'));
        await wait(find.widgetWithText(TextFormField, 'Account number'));
        await wait(find.text(choice.name));
        expect(fieldValue('Account number'), '000012345678');
        expect(fieldValue('Account holder'), 'Meridian Trading');
        expect(fieldValue('UPI payee name'), 'Meridian Trading');
        await wait(find.text('Replace logo'));
        await snapshot('reopened-general-company-settings');
        stdout.writeln(
          'Verified ${choice.name} on ${bill['name']}, balance INR ${payment.queryParameters['am']}; Meridian branding persisted after switching companies, and Kaveri retained its independent profile in Knitting and General ERP.',
        );
      } finally {
        // Only restore the version written by this rehearsal; a subsequent editor wins.
        if (restoreRevision != null) {
          await t.runAsync(
            () => api.saveInvoiceSettings(company, original, restoreRevision!),
          );
          expect(
            (await t.runAsync(() => api.invoiceSettings(company)))!['settings'],
            original,
          );
        }
        final finalKnitting = (await t.runAsync(
          () => knittingOwner.api.invoiceSettings('Kaveri Loomworks'),
        ))!;
        expect(finalKnitting['settings'], knittingOriginal);
        expect(finalKnitting['revision'], knittingBaseline['revision']);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
