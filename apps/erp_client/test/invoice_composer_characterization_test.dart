import 'dart:async';

import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart' show ErpException;
import 'package:erp_client/invoice_composer.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'invoice_composer_test.dart' show ComposerApi;

class _Api extends ComposerApi {
  _Api() {
    access('B', 1);
    access('A', 1);
  }
  final reads = <String>[];
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

  final styles = <(String, String, String)>[];
  Completer<Map<String, dynamic>>? pending;
  String currentStyle = 'ledger';
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
  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) {
    reads.add(company);
    return company == 'A' && pending != null
        ? pending!.future
        : Future.value({
            'posting_date': '2026-11-17',
            'currency': 'INR',
            'template_id': currentStyle,
          });
  }

  @override
  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson({'doctype': doctype, 'fields': []});
  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': {'doctype': doctype, 'company': company, '__islocal': 1},
    'permissions': {'create': 1, 'write': 1},
  });
  @override
  Future<void> setInvoiceTemplate(
    String company,
    String name,
    String templateId,
  ) async {
    styles.add((company, name, templateId));
  }
}

class _AckApi extends _Api {
  _AckApi({this.refreshAfterSave = false, this.interruptAfterSave = false});
  int acknowledgements = 0;
  int businessWrites = 0;
  bool refreshAfterSave, interruptAfterSave, completed = false;
  @override
  bool supportsOperationRecovery(String company) => true;
  @override
  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String requestId, {
    String? doctype,
    String? name,
    String? action,
  }) async => {'state': 'prepared'};
  @override
  Future<String> saveInvoiceDraft(
    Map<String, Object?> draft,
    String requestId,
    String review,
  ) async {
    businessWrites++;
    completed = true;
    if (refreshAfterSave) {
      refreshAfterSave = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => access('A', 2));
    }
    if (interruptAfterSave) throw const ErpException('Response interrupted');
    return 'SINV-CONFIRMED';
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String requestId,
  ) async => {
    'state': completed ? 'completed' : 'prepared',
    if (completed) 'result': {'name': 'SINV-CONFIRMED'},
  };
  @override
  Future<void> acknowledgeOperation(String company, String requestId) async {
    acknowledgements++;
  }
}

void main() {
  testWidgets(
    'prepared save can be left for Pending operations while access is unavailable',
    (t) async {
      final api = _AckApi(interruptAfterSave: true);
      addTearDown(api.close);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 1400);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceComposer(api: api, company: 'A'),
                  ),
                ),
                child: const Text('Create invoice'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Create invoice'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Customer',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        'Service',
      );
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save draft'));
      await t.pumpAndSettle();
      expect(find.text('Check save status'), findsOneWidget);
      api.pauseAccess();
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Leave and check later'), findsOneWidget);
      await t.tap(find.text('Leave and check later'));
      await t.pumpAndSettle();
      expect(find.text('Create invoice'), findsOneWidget);
      expect(api.businessWrites, 1);
      expect(api.acknowledgements, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'access refresh between receipt and its frame keeps the confirmed save recoverable',
    (t) async {
      final api = _AckApi(refreshAfterSave: true);
      addTearDown(api.close);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 1400);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceComposer(api: api, company: 'A'),
                  ),
                ),
                child: const Text('Create invoice'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Create invoice'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Customer',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        'Service',
      );
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save draft'));
      await t.pumpAndSettle();
      expect(find.text('New sales invoice'), findsOneWidget);
      expect(find.text('Check save status'), findsOneWidget);
      expect(api.acknowledgements, 0);
      await t.tap(find.text('Check save status'));
      await t.pumpAndSettle();
      expect(find.text('Create invoice'), findsOneWidget);
      expect(api.businessWrites, 1);
      expect(api.acknowledgements, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'access replacement dismisses an owned dialog while revalidation is pending',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceComposer(api: api, company: 'A'),
                  ),
                ),
                child: const Text('Create invoice'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Create invoice'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Protected customer',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '2');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Keep editing'), findsOneWidget);
      final pending = Completer<Map<String, dynamic>>();
      api.pending = pending;
      api.access('A', 2);
      try {
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('Keep editing'), findsNothing);
      } finally {
        pending.complete({
          'posting_date': '2026-11-17',
          'template_id': 'ledger',
        });
        await t.pumpAndSettle();
      }
    },
  );
  Future<void> size(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1100, 1400);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
  }

  testWidgets('company replacement dismisses the old composer discard dialog', (
    t,
  ) async {
    await size(t);
    final api = _Api(), company = ValueNotifier('A');
    addTearDown(api.close);
    addTearDown(company.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ValueListenableBuilder(
                    valueListenable: company,
                    builder: (_, value, child) =>
                        InvoiceComposer(api: api, company: value),
                  ),
                ),
              ),
              child: const Text('Create invoice'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Create invoice'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Customer'),
      'Protected A customer',
    );
    await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '2');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Keep editing'), findsOneWidget);
    company.value = 'B';
    await t.pumpAndSettle();
    expect(find.text('Keep editing'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'successful composer acknowledges its rendered receipt after a zero-duration route closes',
    (t) async {
      await size(t);
      final api = _AckApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  PageRouteBuilder(
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (_, animation, secondaryAnimation) =>
                        InvoiceComposer(api: api, company: 'A'),
                  ),
                ),
                child: const Text('Create invoice'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Create invoice'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Customer',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        'Service',
      );
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save draft'));
      await t.pumpAndSettle();
      expect(find.text('Draft SINV-CONFIRMED saved.'), findsOneWidget);
      expect(find.text('Create invoice'), findsOneWidget);
      expect(api.acknowledgements, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('old composer access refresh cannot hide a replacement company', (
    t,
  ) async {
    await size(t);
    final api = _Api();
    addTearDown(api.close);
    Widget view(String company) => MaterialApp(
      home: InvoiceComposer(api: api, company: company),
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
      expect(find.text('B'), findsOneWidget);
    } finally {
      old.complete({'posting_date': '2026-11-16', 'template_id': 'ledger'});
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'access revalidation publishes fresh defaults and rejects an older defaults read',
    (t) async {
      await size(t);
      final old = Completer<Map<String, dynamic>>();
      final api = _Api()..pending = old;
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceComposer(api: api, company: 'A'),
        ),
      );
      await t.pump();
      api.pending = null;
      api.currentStyle = 'folio';
      api.access('A', 2);
      await t.pumpAndSettle();
      old.complete({'posting_date': '2026-11-16', 'template_id': 'ledger'});
      await t.pumpAndSettle();
      expect(api.reads.where((v) => v == 'A').length, greaterThanOrEqualTo(2));
      expect(find.text('Company default · Press Folio'), findsOneWidget);
      expect(find.text('Invoice date · 2026-11-17'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'returning from old full editor cannot style or dismiss a replacement composer',
    (t) async {
      await size(t);
      final api = _Api(), navigator = GlobalKey<NavigatorState>();
      addTearDown(api.close);
      var company = 'A';
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: StatefulBuilder(
            builder: (_, update) {
              change = update;
              return InvoiceComposer(
                api: api,
                company: company,
                templateId: 'grove',
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Full editor'));
      await t.pumpAndSettle();
      final editor = t.widget<DocumentEditor>(find.byType(DocumentEditor));
      expect(editor.company, 'A');
      expect(editor.onCreated, isNotNull);
      editor.onCreated!(
        NativeDocument.fromJson({
          'doc': {'doctype': 'Sales Invoice', 'company': 'A', 'name': 'SINV-A'},
          'permissions': {'read': 1},
        }),
      );
      change(() => company = 'B');
      await t.pumpAndSettle();
      navigator.currentState!.pop();
      await t.pumpAndSettle();
      expect(api.styles, isEmpty);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('New sales invoice'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
