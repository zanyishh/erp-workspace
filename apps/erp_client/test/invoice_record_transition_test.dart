import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Invoices extends ErpApi {
  _Invoices() : super(Uri.parse('http://127.0.0.1:8081'));
  final document = Completer<NativeDocument>();
  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) async => {
    'company': company,
    'rows': [
      for (var i = 0; i < 20; i++)
        {'name': 'SINV-TEST-2026-$i', 'customer_name': 'Synthetic Textiles'},
    ],
    'can_create': false,
    'has_more': false,
  };

  @override
  Future<NativeSchema> nativeSchema(String type) async =>
      NativeSchema.fromJson({
        'doctype': type,
        'fields': [
          {
            'fieldname': 'description',
            'label': 'Description',
            'fieldtype': 'Data',
          },
        ],
      });

  @override
  Future<NativeDocument> nativeDocument(
    String type, {
    String? name,
    String? company,
    String? treeParent,
  }) => document.future;
}

void main() {
  testWidgets('a rejected native invoice read removes the in-flight label', (
    t,
  ) async {
    final api = _Invoices();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme.copyWith(platform: TargetPlatform.iOS),
        home: InvoiceHub(api: api, company: 'Test Mill', canCreate: false),
      ),
    );
    await t.pumpAndSettle();
    const name = 'SINV-TEST-2026-0';
    final tag = t
        .widget<Hero>(
          find.ancestor(of: find.text(name), matching: find.byType(Hero)),
        )
        .tag;
    final flight = find.byKey(ValueKey<Object>((tag, 'flight')));
    await t.tap(find.text(name));
    await t.pump();
    await t.pump(const Duration(milliseconds: 70));
    expect(flight, findsOneWidget);
    api.document.completeError(
      const ErpException('Access denied', permissionDenied: true),
    );
    await t.pump();
    await t.pump();
    expect(flight, findsNothing);
    await t.pumpAndSettle();
    expect(find.text(name), findsNothing);
    expect(find.textContaining('Access denied'), findsOneWidget);
  });
  for (final reduced in [false, true]) {
    testWidgets(
      'invoice identity follows a delayed editor and returns to its scrolled row with reduced motion $reduced',
      (t) async {
        final api = _Invoices();
        addTearDown(api.close);
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 844);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        await t.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme.copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: InvoiceHub(api: api, company: 'Test Mill', canCreate: false),
          ),
        );
        await t.pumpAndSettle();
        const name = 'SINV-TEST-2026-15';
        final row = find.text(name);
        await t.dragUntilVisible(
          row,
          find.byType(ListView),
          const Offset(0, -140),
        );
        await t.pumpAndSettle();
        final position = t.getTopLeft(row);
        final identity = find.ancestor(
          of: find.text(name),
          matching: find.byType(Hero),
        );
        final tag = reduced ? null : t.widget<Hero>(identity).tag;
        expect(identity, reduced ? findsNothing : findsOneWidget);
        await t.tap(find.text(name));
        await t.pump();
        await t.pump(const Duration(milliseconds: 84));
        expect(find.byType(DocumentEditor), findsOneWidget);
        final flying = find.byKey(ValueKey<Object>((tag, 'flight')));
        expect(flying, reduced ? findsNothing : findsOneWidget);
        if (!reduced) {
          final first = t.getRect(flying);
          await t.pump(const Duration(milliseconds: 60));
          expect(t.getRect(flying).top, lessThan(first.top));
        }
        api.document.complete(
          NativeDocument.fromJson({
            'doc': {
              'doctype': 'Sales Invoice',
              'company': 'Test Mill',
              'name': name,
            },
            'permissions': {'read': true, 'write': true},
          }),
        );
        await t.pumpAndSettle();
        expect(find.byType(NativeDocumentForm), findsOneWidget);
        if (!reduced) expect(t.widget<Hero>(identity).tag, tag);
        await t.binding.handlePopRoute();
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        expect(flying, reduced ? findsNothing : findsOneWidget);
        if (!reduced) {
          final first = t.getRect(flying);
          await t.pump(const Duration(milliseconds: 70));
          expect(t.getRect(flying).top, greaterThan(first.top));
        }
        await t.pumpAndSettle();
        expect(find.byType(DocumentEditor), findsNothing);
        expect(t.getTopLeft(row), position);
        expect(t.takeException(), isNull);
      },
    );
  }
}
