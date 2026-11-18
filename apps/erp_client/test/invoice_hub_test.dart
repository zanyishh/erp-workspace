import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_composer.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/invoice_gallery.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InvoiceApi extends ErpApi {
  _InvoiceApi() : super(Uri.parse('http://localhost:8081'));
  final calls = <({String query, String status, int offset})>[];
  String? payableTotal;
  bool mixedPrintRights = false;
  bool allowCreate = true, allowPrint = true;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<NativeCatalog> nativeCatalog({String? company}) async =>
      NativeCatalog.fromJson({
        'version': 1,
        'types': [
          {
            'name': 'Sales Invoice',
            'module': 'Accounts',
            'create': allowCreate,
          },
        ],
        'reports': [],
      });

  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) async => {
    'posting_date': '2026-11-17',
    'template_id': 'ledger',
  };
  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) async {
    expect(company, 'Kaveri Loomworks');
    if (pending != null) return pending!.future;
    calls.add((query: query, status: status, offset: start));
    return {
      'rows': query == 'absent'
          ? []
          : [
              {
                'name': 'INV-${start + 1}',
                'customer_name': 'Vaigai Textiles',
                'posting_date': '2026-11-14',
                'status': status == 'All' ? 'Unpaid' : status,
                'currency': 'INR',
                'precision': 2,
                'grand_total': '123400.5',
                if (payableTotal != null) 'payable_total': payableTotal,
                'can_print': allowPrint,
              },
              if (mixedPrintRights)
                {
                  'name': 'CREDIT-2',
                  'customer_name': 'Example Books',
                  'posting_date': '2026-11-11',
                  'status': 'Draft',
                  'currency': 'INR',
                  'grand_total': '7',
                  'can_print': false,
                },
            ],
      'statuses': ['All', 'Draft', 'Unpaid', 'Paid'],
      'has_more': query.isEmpty && start == 0,
      'can_create': allowCreate,
    };
  }
}

void main() {
  late _InvoiceApi api;
  setUp(() => api = _InvoiceApi());
  tearDown(() => api.close());
  Future<void> hub(
    WidgetTester t, {
    Size size = const Size(1100, 800),
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: InvoiceHub(
          api: api,
          company: 'Kaveri Loomworks',
          canCreate: api.allowCreate,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final create in [false, true]) {
    testWidgets(
      'company catalog opens invoice ${create ? 'composer' : 'register'}',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: NativeCatalogScreen(
              api: api,
              company: 'Kaveri Loomworks',
              create: create,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Sales Invoice'));
        await t.pumpAndSettle();
        if (create) {
          expect(
            t.widget<InvoiceComposer>(find.byType(InvoiceComposer)).company,
            'Kaveri Loomworks',
          );
        } else {
          expect(find.byType(InvoiceHub), findsOneWidget);
          expect(find.text('INV-1'), findsOneWidget);
          await t.tap(find.text('New invoice'));
          await t.pumpAndSettle();
          expect(
            t.widget<InvoiceComposer>(find.byType(InvoiceComposer)).company,
            'Kaveri Loomworks',
          );
        }
      },
    );
  }

  testWidgets('register shows the payable total with exact decimal digits', (
    t,
  ) async {
    api.payableTotal = '9007199254740993.25';
    await hub(t);
    expect(find.text('₹9,00,71,99,25,47,40,993.25'), findsOneWidget);
  });

  testWidgets(
    'phone totals and status use one right edge across print permissions',
    (t) async {
      api.mixedPrintRights = true;
      await hub(t, size: const Size(390, 844));
      final amountEdge = t.getTopRight(find.text('₹1,23,400.50')).dx;
      expect(t.getTopRight(find.text('₹7.00')).dx, closeTo(amountEdge, .1));
      expect(t.getTopRight(find.text('Unpaid')).dx, closeTo(amountEdge, .1));
      expect(t.getTopRight(find.text('Draft')).dx, closeTo(amountEdge, .1));
    },
  );

  testWidgets('desktop register columns align even when print access differs', (
    t,
  ) async {
    for (final printable in [true, false]) {
      api.allowPrint = printable;
      await hub(t);
      await t.tap(find.byTooltip('Refresh invoices'));
      await t.pumpAndSettle();
      final issued = t.getTopLeft(find.text('Issued')).dx;
      expect(t.getTopLeft(find.text('14 Nov 2026')).dx, closeTo(issued, .1));
      final total = t.getTopRight(find.text('Total')).dx;
      expect(t.getTopRight(find.text('₹1,23,400.50')).dx, closeTo(total, .1));
    }
  });

  testWidgets('invoice refresh retains rows and labels a failed refresh', (
    t,
  ) async {
    await hub(t);
    api.pending = Completer<Map<String, dynamic>>();
    await t.tap(find.byTooltip('Refresh invoices'));
    await t.pump();
    expect(find.text('INV-1'), findsOneWidget);
    api.pending!.completeError(
      const FormatException('Invoice refresh unavailable'),
    );
    await t.pumpAndSettle();
    expect(find.text('INV-1'), findsOneWidget);
    expect(find.textContaining('Invoice refresh unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'invoice register searches, filters, pages and formats posted amounts',
    (t) async {
      await hub(t);
      expect(find.text('₹1,23,400.50'), findsOneWidget);
      expect(find.byTooltip('Preview INV-1'), findsOneWidget);
      await t.tap(find.byTooltip('Next invoices'));
      await t.pumpAndSettle();
      expect(api.calls.last.offset, 25);
      expect(find.text('INV-26'), findsOneWidget);
      await t.tap(find.byTooltip('Filter invoice status'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Paid'));
      await t.pumpAndSettle();
      expect(api.calls.last.status, 'Paid');
      expect(api.calls.last.offset, 0);
      await t.enterText(find.byType(TextField), 'absent');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('No matching invoices'), findsOneWidget);
      await t.tap(find.text('Show all invoices'));
      await t.pumpAndSettle();
      expect(api.calls.last, (query: '', status: 'All', offset: 0));
    },
  );

  testWidgets(
    'all 15 stationery previews are reachable on a phone and posting permissions are respected',
    (t) async {
      api.allowPrint = false;
      api.allowCreate = false;
      await hub(t, size: const Size(360, 640), scale: 1.4);
      expect(find.byTooltip('Preview INV-1'), findsNothing);
      expect(find.text('New invoice'), findsNothing);
      await t.tap(find.text('Templates'));
      await t.pumpAndSettle();
      expect(find.byType(InvoiceGallery), findsOneWidget);
      expect(invoiceTemplates.length, 15);
      expect(invoiceTemplates.map((e) => e.id).toSet().length, 15);
      for (final tplt in invoiceTemplates) {
        await t.scrollUntilVisible(
          find.text(tplt.name),
          230,
          scrollable: find
              .descendant(
                of: find.byType(GridView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text(tplt.name), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'phone register keeps the operation in the toolbar and scrolls controls with records',
    (t) async {
      await hub(t, size: const Size(360, 640));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Invoices'),
        ),
        findsOneWidget,
      );
      expect(find.text('Kaveri Loomworks'), findsOneWidget);
      final header = t.getTopLeft(find.text('New invoice')).dy;
      await t.drag(find.text('INV-1'), const Offset(0, -200));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('New invoice')).dy, lessThan(header));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'a short phone can still reach the templates and search without overflow',
    (t) async {
      await hub(t, size: const Size(320, 510), scale: 1.4);
      t.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(TextField));
      expect(t.takeException(), isNull);
    },
  );
}
