import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api([int port = 8081]) : super(Uri.parse('http://127.0.0.1:$port'));
  final reads = <(String, String, String)>[];
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> data(
    String company,
    String name, {
    bool imported = false,
  }) => {
    ...sampleInvoiceData(),
    'company': company,
    'seller_name': company,
    'name': name,
    'can_set_template': true,
    'template_override': '',
    'template_id': 'ledger',
    if (imported) 'source_record': name,
    if (imported) 'source_copy': true,
    if (imported) 'source_reference': 'Original $name',
  };
  @override
  Future<Map<String, dynamic>> invoicePrintData(String company, String name) {
    reads.add(('native', company, name));
    return pending?.future ?? Future.value(data(company, name));
  }

  @override
  Future<Map<String, dynamic>> importedInvoicePrintData(
    String company,
    String name,
  ) {
    reads.add(('original', company, name));
    return pending?.future ?? Future.value(data(company, name, imported: true));
  }
}

void main() {
  testWidgets(
    'submission preview refuses a newer draft instead of showing its paper',
    (t) async {
      final api = _Api()..pending = Completer<Map<String, dynamic>>();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoicePreviewScreen(
            api: api,
            company: 'A',
            invoice: 'INV-1',
            draftRevision: 'old',
          ),
        ),
      );
      api.pending!.complete({
        ...api.data('A', 'INV-1'),
        'modified': 'new',
        'docstatus': 0,
      });
      await t.pumpAndSettle();
      expect(find.textContaining('This draft has changed.'), findsOneWidget);
      expect(find.text('Export PDF'), findsNothing);
    },
  );

  for (final width in [360.0, 1024.0]) {
    testWidgets(
      'paper size picker changes the active preview at width $width',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 740);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        final api = _Api();
        addTearDown(api.close);
        await t.pumpWidget(
          MaterialApp(
            home: InvoicePreviewScreen(
              api: api,
              company: 'A',
              invoice: 'INV-1',
            ),
          ),
        );
        await t.pump();
        Future<void> openPaper(String current) async {
          if (width < 600) {
            await t.tap(find.byTooltip('More invoice actions'));
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            await t.tap(find.text('Paper size · $current'));
          } else {
            await t.tap(find.text(current));
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
        }

        await openPaper('A4');
        await t.tap(find.text('58 mm receipt').last);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await openPaper('58 mm receipt');
        final selection = t.widget<ListTile>(
          find.widgetWithText(ListTile, '58 mm receipt'),
        );
        expect(selection.selected, isTrue);
        expect(api.reads, [('native', 'A', 'INV-1')]);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final change in ['company', 'invoice', 'source', 'api']) {
    testWidgets(
      'invoice preview replaces its pending source when $change changes',
      (t) async {
        final first = _Api(), second = _Api(8082);
        addTearDown(first.close);
        addTearDown(second.close);
        final old = Completer<Map<String, dynamic>>();
        first.pending = old;
        Widget view(
          _Api api,
          String company,
          String? invoice,
          String? source,
        ) => MaterialApp(
          home: InvoicePreviewScreen(
            api: api,
            company: company,
            invoice: invoice,
            importedRecord: source,
          ),
        );
        await t.pumpWidget(view(first, 'A', 'INV-1', null));
        await t.pump();
        first.pending = null;
        final api = change == 'api' ? second : first;
        final company = change == 'company' ? 'B' : 'A';
        final invoice = change == 'invoice'
            ? 'INV-2'
            : change == 'source'
            ? null
            : 'INV-1';
        final source = change == 'source' ? 'history-1' : null;
        await t.pumpWidget(view(api, company, invoice, source));
        old.complete(first.data('A', 'INV-1'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(
          api.reads,
          contains((
            source == null ? 'native' : 'original',
            company,
            source ?? invoice!,
          )),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
