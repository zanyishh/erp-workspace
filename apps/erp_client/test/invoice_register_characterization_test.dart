import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081')) {
    access('B', 1);
    access('A', 1);
  }
  final reads = <String>[];
  bool allowCreate = false;
  final observers = <VoidCallback>[];
  @override
  void addAccessListener(VoidCallback listener) {
    super.addAccessListener(listener);
    observers.add(listener);
  }

  @override
  void removeAccessListener(VoidCallback listener) {
    super.removeAccessListener(listener);
    observers.remove(listener);
  }

  void pauseAccess() {
    accessReady = false;
    accessRevision++;
    for (final listener in List.of(observers)) {
      listener();
    }
  }

  Completer<Map<String, dynamic>>? pending;
  Completer<Map<String, dynamic>>? profilePending;
  void access(String company, int version) => publishContext(
    WorkspaceContext.fromJson({
      'company': company,
      'access_fingerprint': '$company-$version',
      'companies': [
        {'name': 'A'},
        {'name': 'B'},
      ],
    }),
  );
  Map<String, dynamic> page(String company) => {
    'rows': [
      {
        'name': 'Invoice $company',
        'customer_name': 'Synthetic $company',
        'status': 'Draft',
        'can_print': false,
      },
    ],
    'statuses': ['All', 'Draft'],
    'has_more': false,
    'can_create': allowCreate,
    'can_manage_settings': true,
  };
  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) {
    reads.add(company);
    return company == 'A' && pending != null
        ? pending!.future
        : Future.value(page(company));
  }

  @override
  Future<Map<String, dynamic>> invoiceSettings(String company) async =>
      profilePending?.future ??
      {
        'company': company,
        'revision': 'r',
        'can_manage': false,
        'settings': <String, dynamic>{},
      };
  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) async => {
    'posting_date': '2026-11-16',
    'template_id': 'ledger',
  };
}

void main() {
  testWidgets(
    'template route keeps Create when refresh completes before its deferred build',
    (t) async {
      final api = _Api()..allowCreate = true;
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceHub(api: api, company: 'A', canCreate: true),
        ),
      );
      await t.pumpAndSettle();
      final refresh = Completer<Map<String, dynamic>>();
      api.pending = refresh;
      await t.tap(find.byTooltip('Refresh invoices'));
      await t.pump();
      await t.tap(find.text('Templates'));
      await t.pumpAndSettle();
      // Hold the legacy preview read so this test never waits for PDF rasterization.
      api.profilePending = Completer<Map<String, dynamic>>();
      await t.tap(find.text('Violet Canopy'));
      api.pending = null;
      refresh.complete(api.page('A'));
      final preview = find.byType(InvoicePreviewScreen, skipOffstage: false);
      for (var i = 0; i < 8 && preview.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(preview, findsOneWidget);
      expect(t.widget<InvoicePreviewScreen>(preview).onCreate, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'session recovery never renders an unavailable retained invoice page',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceHub(api: api, company: 'A', canCreate: false),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Invoice A'), findsOneWidget);
      final reads = api.reads.length;
      api.pauseAccess();
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Invoice A'), findsNothing);
      expect(api.reads, hasLength(reads));
      api.access('A', 3);
      await t.pumpAndSettle();
      expect(find.text('Invoice A'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'an old invoice access refresh cannot gate a replacement company',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      Widget view(String company) => MaterialApp(
        home: InvoiceHub(api: api, company: company, canCreate: false),
      );
      await t.pumpWidget(view('A'));
      await t.pumpAndSettle();
      final old = Completer<Map<String, dynamic>>();
      api.pending = old;
      api.access('A', 2);
      api.access('B', 2);
      await t.pump();
      await t.pumpWidget(view('B'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 10));
      }
      try {
        expect(api.reads, contains('B'));
        expect(find.text('Invoice B'), findsOneWidget);
      } finally {
        old.complete(api.page('A'));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'settings return from an old company cannot refresh or confirm the new company',
    (t) async {
      final api = _Api(), navigator = GlobalKey<NavigatorState>();
      addTearDown(api.close);
      var company = 'A';
      late StateSetter changeHome;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: StatefulBuilder(
            builder: (context, setState) {
              changeHome = setState;
              return InvoiceHub(api: api, company: company, canCreate: false);
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Invoice settings'));
      await t.pumpAndSettle();
      changeHome(() => company = 'B');
      await t.pumpAndSettle();
      final before = api.reads.where((v) => v == 'B').length;
      navigator.currentState!.pop(true);
      await t.pumpAndSettle();
      expect(find.text('Invoice settings saved for B.'), findsNothing);
      expect(api.reads.where((v) => v == 'B').length, before);
      expect(find.text('Invoice B'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
