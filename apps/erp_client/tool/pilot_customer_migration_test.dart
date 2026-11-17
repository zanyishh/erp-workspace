// Explicit, read-only rehearsal against the separate local customer workspace.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/imported_history.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  final binding = _ConnectedBinding();
  final enabled = Platform.environment['ERP_CUSTOMER_PILOT'] == '1';
  const channel = MethodChannel('org.localerp.workspace/local');
  setUp(() {
    final home = Platform.environment['HOME']!;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'applicationSupport'
          ? '$home/Library/Containers/org.localerp.erpClient/Data/Library/Application Support'
          : null,
    );
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'fresh customer launch, all four companies, original records, shared cash and General ERP',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> wait(Finder finder) async {
        for (var i = 0; i < 500; i++) {
          await t.pump(const Duration(milliseconds: 50));
          expect(find.byType(SignInScreen), findsNothing);
          if (finder.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        fail('The expected customer screen was unavailable: $finder');
      }

      Future<void> tap(Finder finder) async {
        await wait(finder);
        await t.ensureVisible(finder.first);
        await t.tap(finder.first);
        await t.pump(const Duration(milliseconds: 250));
      }

      await t.pumpWidget(const ErpWorkspaceApp());
      await wait(find.byType(KnittingScreen));
      var mill = t.widget<KnittingScreen>(find.byType(KnittingScreen));
      final companies = mill.workspace.companies
          .map((row) => row['name'] as String)
          .toList();
      expect(companies.length, 4);
      expect(mill.api.account, 'customer-owner@workspace.example.invalid');
      for (final company in companies) {
        mill = t.widget<KnittingScreen>(find.byType(KnittingScreen));
        if (mill.workspace.company != company) {
          await tap(find.text(mill.workspace.company!).first);
          await wait(find.text('Choose company'));
          await tap(find.widgetWithText(SimpleDialogOption, company));
          for (var i = 0; i < 500; i++) {
            await t.pump(const Duration(milliseconds: 50));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            if (find.byType(KnittingScreen).evaluate().isNotEmpty &&
                t
                        .widget<KnittingScreen>(find.byType(KnittingScreen))
                        .workspace
                        .company ==
                    company) {
              break;
            }
          }
        }
        expect(
          t
              .widget<KnittingScreen>(find.byType(KnittingScreen))
              .workspace
              .company,
          company,
        );
        await tap(find.text('Original orders'));
        await wait(find.byType(ImportedHistoryScreen));
        await wait(find.text('Search original references'));
        expect(
          t
              .widget<ImportedHistoryScreen>(find.byType(ImportedHistoryScreen))
              .company,
          company,
        );
        await tap(find.byType(DropdownButtonFormField<String>));
        await tap(find.text('Shared cash').last);
        await wait(find.text('Shared across companies'));
        await wait(find.text('Staff Welfare Expenses'));
        expect(t.takeException(), isNull);
        await t.pageBack();
        await wait(find.byType(KnittingScreen));
        await tap(find.text('General ERP'));
        await wait(find.byType(OverviewScreen));
        expect(
          t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
          company,
        );
        await tap(find.text('Invoices').first);
        await wait(find.byType(InvoiceHub));
        expect(t.widget<InvoiceHub>(find.byType(InvoiceHub)).company, company);
        await t.pageBack();
        await wait(find.byType(OverviewScreen));
        await tap(find.text(company).first);
        await tap(find.text('Open knitting workspace'));
        await wait(find.byType(KnittingScreen));
        expect(t.takeException(), isNull);
      }
      await t.pumpWidget(const SizedBox());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(seconds: 21));
      await t.pump();
    },
    skip: !enabled,
  );

  test('original invoice PDFs preserve saved dates and amounts, including blank descriptions', () async {
    final input = Platform.environment['ERP_CUSTOMER_PILOT_INPUT'];
    final output = Platform.environment['ERP_CUSTOMER_PILOT_OUTPUT'];
    expect(input, isNotNull);
    expect(output, isNotNull);
    final local = await LocalWorkspace.open(workspaceId: 'customer');
    addTearDown(local.api.close);
    final rows = jsonDecode(await File(input!).readAsString()) as List;
    expect(rows.length, greaterThanOrEqualTo(8));
    await Directory(output!).create(recursive: true);
    var index = 0;
    for (final row in rows) {
      final data = await local.api.importedInvoicePrintData(
        row['company'],
        row['name'],
      );
      expect(data['source_copy'], true);
      expect(data['source_record'], row['name']);
      expect(data['posting_date'], row['posting_date']);
      expect(data['grand_total'].toString(), row['grand_total'].toString());
      expect(data['can_set_template'], false);
      for (final tax in data['taxes'] as List) {
        expect((tax['label'] as String).isNotEmpty, true);
        expect(tax['amount'].toString(), matches(RegExp(r'^-?\d+(\.\d+)?$')));
      }
      final pdf = await buildInvoicePdf(
        invoiceTemplateById(data['template_id']),
        data,
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(2000));
      await File('$output/original-${++index}.pdf').writeAsBytes(pdf);
    }
  }, skip: !enabled);
}
