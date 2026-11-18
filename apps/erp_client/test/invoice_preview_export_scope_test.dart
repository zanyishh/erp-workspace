import 'dart:async';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api([int port = 8081]) : super(Uri.parse('http://127.0.0.1:$port'));
  bool denied = false;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> invoicePrintData(
    String company,
    String name,
  ) async {
    reads++;
    if (denied) {
      throw const ErpException(
        'Print access was revoked.',
        permissionDenied: true,
      );
    }
    return {
      ...sampleInvoiceData(),
      'company': company,
      'seller_name': company,
      'name': name,
      'template_id': 'ledger',
      'template_override': '',
      'can_set_template': true,
    };
  }
}

void main() {
  for (final change in ['company', 'api', 'permission']) {
    testWidgets(
      'PDF picker cannot save obsolete invoice bytes after $change changes',
      (t) async {
        final api = _Api(), other = _Api(8082);
        addTearDown(api.close);
        addTearDown(other.close);
        // Complete font I/O outside the fake clock; the test never settles rasterization.
        await t.runAsync(
          () => buildInvoicePdf(
            invoiceTemplateById('ledger'),
            sampleInvoiceData(),
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'erp-invoice-scope-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/must-not-exist.pdf');
        final selected = Completer<String?>();
        var opened = false;
        const channel = MethodChannel('plugins.flutter.io/file_selector');
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'getSavePath') {
            opened = true;
            return selected.future;
          }
          throw MissingPluginException();
        });
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        Widget view(ErpApi client, String company) => MaterialApp(
          home: InvoicePreviewScreen(
            api: client,
            company: company,
            invoice: 'INV-1',
          ),
        );
        await t.pumpWidget(view(api, 'A'));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('Export PDF'), findsOneWidget);
        await t.tap(find.text('Export PDF'));
        for (var i = 0; i < 40 && !opened; i++) {
          await t.pump(const Duration(milliseconds: 20));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(opened, isTrue);
        if (change == 'permission') {
          api.denied = true;
        } else {
          await t.pumpWidget(
            view(
              change == 'api' ? other : api,
              change == 'company' ? 'B' : 'A',
            ),
          );
        }
        selected.complete(file.path);
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(file.existsSync(), isFalse);
        if (change == 'permission') {
          expect(api.reads, 3);
          expect(find.text('Print access was revoked.'), findsOneWidget);
          expect(find.text('Export PDF'), findsNothing);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
