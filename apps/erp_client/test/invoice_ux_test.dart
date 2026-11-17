import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/invoice_composer.dart';
import 'package:erp_client/erp_api.dart';

import 'invoice_composer_test.dart' show ComposerApi;

class _BusyComposerApi extends ComposerApi {
  final pending = Completer<String>();
  @override
  Future<String> saveInvoiceDraft(
    Map<String, Object?> draft,
    String key,
    String review,
  ) => pending.future;
}

class _DelayedDefaultsApi extends ComposerApi {
  final defaults = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) =>
      defaults.future;
}

class _RecoveryComposerApi extends ComposerApi {
  String state = 'prepared';
  bool failPrepare = false;
  int acknowledged = 0;
  @override
  bool supportsOperationRecovery(String company) => true;
  Map<String, dynamic> get operation => {
    'state': state,
    if (state == 'completed') 'result': {'name': 'SINV-RECOVERED'},
  };
  @override
  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String id, {
    String? doctype,
    String? name,
    String? action,
  }) async {
    if (failPrepare) throw const ErpException('Offline');
    return operation;
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String id,
  ) async => operation;
  @override
  Future<Map<String, dynamic>> closeOperation(String company, String id) async {
    if (state == 'prepared') state = 'closed';
    return operation;
  }

  @override
  Future<void> acknowledgeOperation(String company, String id) async {
    acknowledged++;
  }
}

class _DelayedPreparationApi extends _RecoveryComposerApi {
  final prepared = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String id, {
    String? doctype,
    String? name,
    String? action,
  }) => prepared.future;
}

Future<void> _open(WidgetTester t, ErpApi api) async {
  addTearDown(api.close);
  t.view.physicalSize = const Size(1000, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              c,
              MaterialPageRoute(
                builder: (_) =>
                    InvoiceComposer(api: api, company: 'Sample company'),
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
}

Future<void> _enter(WidgetTester t) async {
  await t.enterText(
    find.widgetWithText(TextFormField, 'Customer'),
    'Sample customer',
  );
  await t.enterText(
    find.widgetWithText(TextFormField, 'Item or service'),
    'Service',
  );
  await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '2');
}

void main() {
  testWidgets('review waits for an invoice date while defaults are delayed', (
    t,
  ) async {
    final api = _DelayedDefaultsApi();
    await _open(t, api);
    await _enter(t);
    await t.pump();
    final review = find.widgetWithText(FilledButton, 'Review invoice');
    expect(t.widget<FilledButton>(review).onPressed, isNull);
    expect(find.text('Choose an invoice date to continue.'), findsOneWidget);
    api.defaults.complete({
      'posting_date': '2026-11-16',
      'template_id': 'ledger',
    });
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(review).onPressed, isNotNull);
    expect(find.text('Choose an invoice date to continue.'), findsNothing);
  });
  testWidgets(
    'late preparation cannot post a replacement draft after a company round trip',
    (t) async {
      final api = _DelayedPreparationApi();
      final company = ValueNotifier('Sample company');
      addTearDown(api.close);
      addTearDown(company.dispose);
      t.view.physicalSize = const Size(1000, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: company,
            builder: (_, value, _) => InvoiceComposer(api: api, company: value),
          ),
        ),
      );
      await t.pumpAndSettle();
      await _enter(t);
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save draft'));
      await t.pump();
      company.value = 'Second company';
      await t.pumpAndSettle();
      company.value = 'Sample company';
      await t.pumpAndSettle();
      await _enter(t);
      api.prepared.complete({'state': 'prepared'});
      await t.pumpAndSettle();
      expect(api.saves, isEmpty);
      expect(find.text('Sample customer'), findsOneWidget);
      expect(find.text('Review invoice'), findsOneWidget);
    },
  );
  testWidgets('a lost invoice response is checked without a second save', (
    t,
  ) async {
    final api = _RecoveryComposerApi();
    await _open(t, api);
    await _enter(t);
    await t.tap(find.text('Review invoice'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save draft'));
    await t.pumpAndSettle();
    expect(api.saves.length, 1);
    expect(find.text('Check save status'), findsOneWidget);
    api.state = 'completed';
    await t.tap(find.text('Check save status'));
    await t.pumpAndSettle();
    expect(api.saves.length, 1);
    expect(find.text('Create invoice'), findsOneWidget);
    expect(find.text('Draft SINV-RECOVERED saved.'), findsOneWidget);
    expect(api.acknowledged, 1);
  });
  testWidgets('prepared invoice cannot be edited until closure is confirmed', (
    t,
  ) async {
    final api = _RecoveryComposerApi();
    await _open(t, api);
    await _enter(t);
    await t.tap(find.text('Review invoice'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save draft'));
    await t.pumpAndSettle();
    await t.tap(find.text('Check save status'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Quantity'))
          .enabled,
      false,
    );
    await t.tap(find.text('Close unposted request'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Quantity'))
          .enabled,
      true,
    );
    expect(find.text('Sample customer'), findsOneWidget);
    expect(api.saves.length, 1);
  });
  testWidgets('failed invoice preparation never sends a business write', (
    t,
  ) async {
    final api = _RecoveryComposerApi()..failPrepare = true;
    await _open(t, api);
    await _enter(t);
    await t.tap(find.text('Review invoice'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save draft'));
    await t.pumpAndSettle();
    expect(api.saves, isEmpty);
    expect(
      t
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Quantity'))
          .enabled,
      true,
    );
  });
  testWidgets('invoice Back preserves changes until explicit discard', (
    t,
  ) async {
    await _open(t, ComposerApi());
    await _enter(t);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Keep editing'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('Sample customer'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Discard changes'));
    await t.pumpAndSettle();
    expect(find.text('Create invoice'), findsOneWidget);
  });

  testWidgets('a print-template-only edit is protected on Back', (t) async {
    await _open(t, ComposerApi());
    await t.tap(find.text('Company default · Cobalt Fold'));
    await t.pumpAndSettle();
    await t.tap(find.text('Trade Ledger').last);
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Discard changes'), findsOneWidget);
  });

  testWidgets('invoice in-flight save cannot be abandoned by Back', (t) async {
    final api = _BusyComposerApi();
    await _open(t, api);
    await _enter(t);
    await t.tap(find.text('Review invoice'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save draft'));
    await t.pump();
    await t.pageBack();
    await t.pump();
    expect(find.text('New sales invoice'), findsOneWidget);
    expect(find.text('Create invoice'), findsNothing);
    api.pending.complete('SINV-SAVED');
    await t.pumpAndSettle();
    expect(find.text('Create invoice'), findsOneWidget);
  });

  testWidgets('removing and undoing an invoice line restores exact values', (
    t,
  ) async {
    await _open(t, ComposerApi());
    await _enter(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Rate override'),
      '54.25',
    );
    await t.tap(find.byTooltip('Remove item 1'));
    await t.pumpAndSettle();
    expect(find.text('Service'), findsNothing);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Service'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('54.25'), findsOneWidget);
  });

  testWidgets('invoice validation identifies the actual invalid fields', (
    t,
  ) async {
    await _open(t, ComposerApi());
    await t.tap(find.text('Review invoice'));
    await t.pumpAndSettle();
    expect(find.text('Choose a customer.'), findsOneWidget);
    expect(find.text('Choose an item or service.'), findsOneWidget);
  });
}
