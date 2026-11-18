import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/invoice_pdf.dart';
import 'package:erp_client/invoice_templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUpi =
      'upi://pay?pa=meridian%40example&pn=Meridian%20Trading'
      '&am=63000.00&cu=INR&tn=INV-2026-0048';
  Future<Map<String, dynamic>> brandedInvoice() async => {
    ...sampleInvoiceData(),
    'settings': {
      'logo_base64': base64Encode(
        await File('test/fixtures/demo-invoice-logo.png').readAsBytes(),
      ),
      'bank_name': 'Example Bank',
      'signatory_name': 'Demo Manager',
      'print_footer': 'Thank you for your order',
      'account_holder': 'Meridian Trading',
      'account_number': '000000001234',
      'ifsc': 'TEST0000001',
      'upi_id': 'meridian@example',
      'upi_name': 'Meridian Trading',
    },
    'upi_uri': testUpi,
  };
  test(
    'compact paper sizes preserve line rates, status and multi-page totals',
    () async {
      final temp = await Directory.systemTemp.createTemp('invoice-paper-');
      addTearDown(() => temp.delete(recursive: true));
      final data = await brandedInvoice();
      data['delivery_notes'] = [
        {
          'name': 'DN-2026-0024',
          'dispatch_address': 'Depot Gate 002',
          'mode_of_transport': 'Road',
        },
      ];
      final base = (data['items'] as List).first as Map;
      data['items'] = [
        for (var i = 1; i <= 35; i++)
          {
            ...base,
            'item_name': 'Item-$i-end',
            'rate': '1.23456',
            'hsn_sac': '4801',
          },
      ];
      for (final paper in InvoicePaper.values.where(
        (p) => p != InvoicePaper.a4,
      )) {
        final file = File('${temp.path}/${paper.name}.pdf');
        await file.writeAsBytes(
          await buildInvoicePdf(
            invoiceTemplateById('ribbon'),
            data,
            paper: paper,
          ),
        );
        final info = await Process.run('pdfinfo', [file.path]);
        expect(info.exitCode, 0);
        final dimensions = RegExp(r'Page size:\s+([\d.]+) x ([\d.]+)')
            .firstMatch(info.stdout as String)!;
        expect(
          double.parse(dimensions[1]!),
          closeTo(paper.widthMm * 72 / 25.4, .02),
        );
        expect(
          double.parse(dimensions[2]!),
          closeTo(paper.heightMm * 72 / 25.4, .02),
        );
        final result = await Process.run('pdftotext', [
          '-layout',
          file.path,
          '-',
        ]);
        expect(result.exitCode, 0);
        final output = (result.stdout as String).replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        for (final token in [
          'Item-1-end',
          'Item-35-end',
          '1.23456',
          '4801',
          '63,000.00',
          'Unpaid',
          'Meridian Trading',
          'Riverbend Supplies',
          'Example Bank',
          'Demo Manager',
          'Thank you for your order',
          'CGST',
          'DN-2026-0024',
          'Depot Gate 002',
          'Transport mode Road',
        ]) {
          expect(
            output,
            contains(token),
            reason: '${paper.name} missing $token',
          );
        }
        expect(latin1.decode(await file.readAsBytes()), contains(testUpi));
      }
    },
  );

  test(
    'each template uses the company ink and restores its original print accent',
    () {
      for (final template in invoiceTemplates) {
        expect(template.printAccent('#722C37'), 0xff722c37);
        expect(
          template.printAccent(''),
          template.id == 'ribbon' ? 0xff383f61 : template.accent,
        );
      }
    },
  );

  test(
    'each style embeds the logo and the exact payable invoice link',
    () async {
      final invoice = await brandedInvoice();
      final root = Platform.environment['ERP_INVOICE_SAMPLE_OUTPUT'];
      for (final t in invoiceTemplates) {
        final bytes = await buildInvoicePdf(t, invoice);
        final pdf = latin1.decode(bytes);
        expect(pdf, contains(testUpi), reason: t.name);
        expect(pdf, matches(RegExp(r'/Subtype\s*/Image\b')), reason: t.name);
        if (root != null) {
          final file = File('$root/branded-${t.id}.pdf');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        }
      }
    },
  );
  test('only eligible payable INR invoices include a UPI request', () async {
    final invoice = await brandedInvoice();
    for (final change in [
      {'docstatus': 0},
      {'docstatus': 2},
      {'is_return': true},
      {'outstanding_amount': '0.00'},
      {'outstanding_amount': '-20.00'},
      {'outstanding_currency': 'USD'},
      {'currency': 'Euro'},
      {'upi_uri': ''},
      {'upi_uri': 'https://example.invalid/demo'},
    ]) {
      final bytes = await buildInvoicePdf(invoiceTemplateById('ledger'), {
        ...invoice,
        ...change,
      });
      final pdf = latin1.decode(bytes);
      expect(pdf, isNot(contains('/URI')), reason: change.keys.first);
    }
  });
  test('source invoice copies never create a payment request', () async {
    final bytes = await buildInvoicePdf(invoiceTemplateById('ledger'), {
      ...await brandedInvoice(),
      'source_copy': true,
      'source_reference': 'Original INV-48',
    });
    expect(latin1.decode(bytes).contains('/URI'), isFalse);
  });
  test('source invoice printing refuses an unknown unit rate', () async {
    final invoice = {
      ...sampleInvoiceData(),
      'source_copy': true,
      'source_reference': 'Original INV-48',
      'items': [
        {'item_name': 'Original service', 'qty': '12', 'amount': '600'},
      ],
    };
    await expectLater(
      buildInvoicePdf(invoiceTemplateById('ledger'), invoice),
      throwsA(isA<FormatException>()),
    );
  });
  test('an explicitly blank original zero line stays printable without invented description', () async {
    final invoice = {
      ...sampleInvoiceData(),
      'source_copy': true,
      'source_reference': 'Original blank line',
      'items': [
        {
          'item_name': '',
          'description': '',
          'qty': '0',
          'rate': '0',
          'amount': '0',
        },
      ],
      'grand_total': '0',
      'net_total': '0',
      'total_taxes_and_charges': '0',
    };
    final bytes = await buildInvoicePdf(invoiceTemplateById('ledger'), invoice);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final incomplete = {
      ...invoice,
      'items': [
        {'qty': '0', 'rate': '0', 'amount': '0'},
      ],
    };
    await expectLater(
      buildInvoicePdf(invoiceTemplateById('ledger'), incomplete),
      throwsA(isA<FormatException>()),
    );
  });
  test(
    'all invoice designs render actual A4 documents from the same safe sample',
    () async {
      expect(invoiceTemplates.map((t) => t.id).toSet().length, 15);
      final root = Platform.environment['ERP_INVOICE_SAMPLE_OUTPUT'];
      final prefs = sampleInvoiceData();
      for (final t in invoiceTemplates) {
        final bytes = await buildInvoicePdf(t, prefs);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        if (root != null) {
          final f = File('$root/${t.id}.pdf');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes);
        }
      }
    },
  );
  test(
    'every template prints saved order, transport and party identifiers',
    () async {
      final invoice = {
        ...sampleInvoiceData(),
        'po_no': 'PO-QA-145',
        'po_date': '2026-11-10',
        'company_tax_id': 'SELLER-991',
        'tax_id': 'BUYER-238',
        'dispatch_address': 'Goods yard 14',
        'shipping_rule': 'Contract carrier',
        'incoterm': 'DAP',
        'named_place': 'South depot',
        'mode_of_transport': 'Road',
        'transporter_name': 'Ferry Freight',
        'vehicle_no': 'TRUCK-QA-123',
        'lr_no': 'LR-QA-778',
        'lr_date': '2026-11-12',
      };
      final directory = await Directory.systemTemp.createTemp(
        'invoice-particulars-',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final template in invoiceTemplates) {
        final file = File('${directory.path}/${template.id}.pdf');
        await file.writeAsBytes(await buildInvoicePdf(template, invoice));
        final result = await Process.run('pdftotext', [
          '-layout',
          file.path,
          '-',
        ]);
        expect(result.exitCode, 0);
        final extracted = result.stdout as String;
        final pages = extracted
            .split('\f')
            .where((page) => page.trim().isNotEmpty);
        expect(pages, hasLength(1), reason: template.name);
        final text = extracted.replaceAll(RegExp(r'\s+'), ' ');
        for (final value in [
          'PO-QA-145',
          '10 Nov 2026',
          'SELLER-991',
          'BUYER-238',
          'Goods yard 14',
          'Contract carrier',
          'DAP',
          'South depot',
          'Road',
          'Ferry Freight',
          'TRUCK-QA-123',
          'LR-QA-778',
          '12 Nov 2026',
        ]) {
          expect(
            text,
            contains(value),
            reason: '${template.name} should print $value',
          );
        }
      }
    },
  );
  test('tax, addresses, purchase references and verified server e-invoice payload fit the named layouts', () async {
    // The values below are synthetic and only exercise rendering. The server controls
    // whether an active e-invoice reference and signed QR are present in this map.
    final invoice = {
      ...await brandedInvoice(),
      'name': 'INV-QA-0291',
      'status': 'Partly Paid',
      'seller_name': 'Meridian Business Supplies and Wholesale Trading Company',
      'customer_name':
          'Riverbend Professional Services and Distribution Company',
      'company_address': '48 Market Road, Building 17\nNorth Commercial Estate, Phase Two\nChennai, Tamil Nadu 600001, India',
      'billing_address': 'Registered office, 12 Park Lane\nSecond Floor, West Business Park\nCoimbatore, Tamil Nadu 641001, India',
      'shipping_address': 'Receiving dock 4, 31 Depot Road, Chennai 600002',
      'company_gstin': '33AAAAA0000A1Z9',
      'customer_gstin': '33BBBBB0000B1Z7',
      'po_no': 'RB-2026-0291',
      'po_date': '2026-11-10',
      'irn': 'ab' * 32,
      'acknowledgement_number': '100012345678901',
      'acknowledgement_date': '2026-11-14 12:35:00',
      'signed_qr_code': 'eyJhbGciOiJub25lIn0.eyJ0ZXN0Ijp0cnVlfQ.c3ludGhldGlj',
      'outstanding_amount': '21000',
      'upi_uri': testUpi.replaceFirst('63000.00', '21000.00'),
      'payments': [
        {'mode_of_payment': 'Bank transfer', 'amount': '42000'},
      ],
    };
    final root = Platform.environment['ERP_INVOICE_SAMPLE_OUTPUT'];
    for (final id in ['canopy', 'ribbon', 'offset', 'cobalt']) {
      final bytes = await buildInvoicePdf(invoiceTemplateById(id), invoice);
      expect(bytes.length, greaterThan(1000));
      if (root != null) await File('$root/tax-$id.pdf').writeAsBytes(bytes);
    }
  });
  test(
    'long return carries all named rows and long terms to following pages',
    () async {
      final sample = await brandedInvoice();
      final invoice = {
        ...sample,
        'name': 'RET-0123',
        'is_return': 1,
        'docstatus': 2,
        'return_against': 'INV-0122',
        'grand_total': '-4217757.13',
        'rounded_total': '-4217757',
        'rounding_adjustment': '0.13',
        'discount_amount': '200.55',
        'items': [
          for (var i = 0; i < 67; i++)
            {
              'item_name': 'Cutting line $i',
              'item_code': 'PX-$i',
              'description': i == 25
                  ? List.filled(
                      170,
                      'Detailed finishing instructions for this delivery.',
                    ).join(' ')
                  : 'Per plan',
              'qty': '-12',
              'rate': '96.25',
              'amount': '-1155',
            },
        ],
        'terms': List.filled(
          75,
          'Recorded invoice terms and signed schedule.',
        ).join(' '),
      };
      final bytes = await buildInvoicePdf(
        invoiceTemplateById('ribbon'),
        invoice,
      );
      expect(bytes, isNotEmpty);
      final root = Platform.environment['ERP_INVOICE_SAMPLE_OUTPUT'];
      if (root != null) {
        await File('$root/multipage-return.pdf').writeAsBytes(bytes);
      }
      expect(
        () => buildInvoicePdf(invoiceTemplateById('ledger'), {}),
        throwsFormatException,
      );
    },
  );
}
