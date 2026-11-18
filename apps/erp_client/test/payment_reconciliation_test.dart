import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/payment_reconciliation.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LedgerApi extends ErpApi {
  LedgerApi() : super(Uri.parse('http://localhost:8081'));
  final writes = <String>[];
  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query, {
    String? parent,
    String? field,
    Map<String, String>? contextValues,
  }) async => [
    {'value': 'Sample party', 'description': ''},
  ];
  @override
  Future<Map<String, dynamic>> reconciliationEntries(
    String company,
    String partyType,
    String party, {
    String paymentQuery = '',
    String invoiceQuery = '',
  }) async => {
    'account': 'Receivable',
    'currency': 'INR',
    'payments': [
      {'name': 'PAY-1', 'balance': writes.isEmpty ? '75' : '50'},
    ],
    'invoices': [
      {'name': 'INV-1', 'balance': writes.isEmpty ? '100' : '75'},
    ],
  };
  @override
  Future<Map<String, dynamic>> allocatePayment(
    String company,
    String partyType,
    String party, {
    required String payment,
    required String invoice,
    required String amount,
    required String expectedPayment,
    required String expectedInvoice,
    String? requestId,
  }) async {
    writes.add(
      '$partyType/$party/$payment/$invoice/$amount/$expectedPayment/$expectedInvoice',
    );
    return {
      'allocated': amount,
      'invoice': invoice,
      'payment_balance': '50',
      'invoice_balance': '75',
    };
  }
}

class RecoverableLedgerApi extends LedgerApi {
  bool loseResponse = true;
  bool prepareFails = false;
  String state = 'completed';
  String? prepared, acknowledged;
  Completer<void>? hold, holdPreparation, holdStatus;
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
  }) async {
    prepared = requestId;
    await holdPreparation?.future;
    if (prepareFails) throw const ErpException('Preparation interrupted');
    return {'state': 'prepared'};
  }

  @override
  Future<Map<String, dynamic>> allocatePayment(
    String company,
    String partyType,
    String party, {
    required String payment,
    required String invoice,
    required String amount,
    required String expectedPayment,
    required String expectedInvoice,
    String? requestId,
  }) async {
    expect(requestId, prepared);
    final result = await super.allocatePayment(
      company,
      partyType,
      party,
      payment: payment,
      invoice: invoice,
      amount: amount,
      expectedPayment: expectedPayment,
      expectedInvoice: expectedInvoice,
      requestId: requestId,
    );
    await hold?.future;
    if (loseResponse) throw const ErpException('Connection interrupted');
    return result;
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String requestId,
  ) async {
    await holdStatus?.future;
    return {
      'state': state,
      if (state == 'completed')
        'result': {
          'payment': 'PAY-1',
          'invoice': 'INV-1',
          'allocated': '25',
          'invoice_balance': '75',
          'payment_balance': '50',
        },
    };
  }

  @override
  Future<Map<String, dynamic>> closeOperation(
    String company,
    String requestId,
  ) async {
    if (state == 'prepared') state = 'closed';
    return operationStatus(company, requestId);
  }

  @override
  Future<void> acknowledgeOperation(String company, String requestId) async {
    acknowledged = requestId;
  }

  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      contextFor(company!)!;
}

Future<void> chooseAllocation(
  WidgetTester tester,
  LedgerApi api, {
  bool pushed = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentReconciliationScreen(
                        api: api,
                        company: 'Synthetic Company',
                      ),
                    ),
                  ),
                  child: const Text('Open reconciliation'),
                ),
              ),
            )
          : PaymentReconciliationScreen(api: api, company: 'Synthetic Company'),
    ),
  );
  if (pushed) {
    await tester.tap(find.text('Open reconciliation'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip('Find Customer'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sample party'));
  await tester.pumpAndSettle();
  for (final option in ['PAY-1 · INR 75', 'INV-1 · INR 100']) {
    final dropdown = find
        .byType(DropdownButtonFormField<String>)
        .at(option.startsWith('PAY') ? 0 : 1);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.widgetWithText(TextField, 'Amount to apply'),
    '25',
  );
  await tester.ensureVisible(find.text('Review allocation'));
}

Future<void> approveAllocation(WidgetTester tester) async {
  await tester.tap(find.text('Review allocation'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apply payment'));
  await tester.pump();
}

TextButton refreshButton(WidgetTester tester) => tester.widget<TextButton>(
  find
      .ancestor(
        of: find.text('Refresh balances'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      )
      .first,
);

void main() {
  testWidgets('company roundtrip cannot submit a delayed old preparation', (
    tester,
  ) async {
    final api = RecoverableLedgerApi()
      ..loseResponse = false
      ..holdPreparation = Completer<void>();
    addTearDown(api.close);
    await chooseAllocation(tester, api);
    await approveAllocation(tester);
    for (final company in ['Other company', 'Synthetic Company']) {
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentReconciliationScreen(api: api, company: company),
        ),
      );
      await tester.pump();
    }
    api.holdPreparation!.complete();
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(api.acknowledged, isNull);
    expect(find.textContaining('applied to INV-1'), findsNothing);
  });

  testWidgets('company roundtrip cannot adopt a delayed old status', (
    tester,
  ) async {
    final api = RecoverableLedgerApi();
    addTearDown(api.close);
    await chooseAllocation(tester, api);
    await approveAllocation(tester);
    await tester.pumpAndSettle();
    api.holdStatus = Completer<void>();
    await tester.ensureVisible(find.text('Check saved outcome'));
    await tester.tap(find.text('Check saved outcome'));
    await tester.pump();
    for (final company in ['Other company', 'Synthetic Company']) {
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentReconciliationScreen(api: api, company: company),
        ),
      );
      await tester.pump();
    }
    api.holdStatus!.complete();
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(api.acknowledged, isNull);
    expect(find.textContaining('applied to INV-1'), findsNothing);
  });

  testWidgets('failed preparation never submits a payment allocation', (
    tester,
  ) async {
    final api = RecoverableLedgerApi()..prepareFails = true;
    addTearDown(api.close);
    await chooseAllocation(tester, api);
    await approveAllocation(tester);
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.text('Check saved outcome'), findsOneWidget);
  });

  testWidgets('in-flight allocation prevents Back from losing its result', (
    tester,
  ) async {
    final api = RecoverableLedgerApi()
      ..loseResponse = false
      ..hold = Completer<void>();
    addTearDown(api.close);
    await chooseAllocation(tester, api, pushed: true);
    await approveAllocation(tester);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(PaymentReconciliationScreen), findsOneWidget);
    api.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Invoice outstanding: INR 75'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open reconciliation'), findsOneWidget);
  });

  testWidgets(
    'access change dismisses an open review and clears protected selections',
    (tester) async {
      final api = RecoverableLedgerApi();
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Synthetic Company',
          'can_reconcile_payments': true,
          'access_fingerprint': 'before',
        }),
      );
      await chooseAllocation(tester, api);
      await tester.tap(find.text('Review allocation'));
      await tester.pumpAndSettle();
      expect(find.text('Apply payment to invoice?'), findsOneWidget);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Synthetic Company',
          'can_reconcile_payments': false,
          'access_fingerprint': 'revoked',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Sample party'), findsNothing);
      expect(api.writes, isEmpty);
    },
  );
  testWidgets(
    'lost response locks allocation until its saved receipt is checked',
    (tester) async {
      final api = RecoverableLedgerApi();
      addTearDown(api.close);
      await chooseAllocation(tester, api);
      await approveAllocation(tester);
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(find.text('Check saved outcome'), findsOneWidget);
      expect(refreshButton(tester).onPressed, isNull);
      await tester.ensureVisible(find.text('Check saved outcome'));
      await tester.tap(find.text('Check saved outcome'));
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(api.acknowledged, api.prepared);
      expect(
        find.textContaining('Invoice outstanding: INR 75'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'prepared status remains locked until a close confirms nothing posted',
    (tester) async {
      final api = RecoverableLedgerApi()..state = 'prepared';
      addTearDown(api.close);
      await chooseAllocation(tester, api);
      await approveAllocation(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check saved outcome'));
      await tester.tap(find.text('Check saved outcome'));
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(refreshButton(tester).onPressed, isNull);
      await tester.ensureVisible(find.text('Close unfinished allocation'));
      await tester.tap(find.text('Close unfinished allocation'));
      await tester.pumpAndSettle();
      expect(api.state, 'closed');
      expect(api.writes, hasLength(1));
      expect(find.text('Check saved outcome'), findsNothing);
    },
  );

  testWidgets('invalid amount focuses its field without posting', (
    tester,
  ) async {
    final api = LedgerApi();
    addTearDown(api.close);
    await chooseAllocation(tester, api);
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount to apply'),
      '999',
    );
    await tester.tap(find.text('Review allocation'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Amount to apply'),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.decoration!.errorText, isNotNull);
    expect(api.writes, isEmpty);
  });
  testWidgets('confirm a partial payment and reload the remaining balances', (
    tester,
  ) async {
    final api = LedgerApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentReconciliationScreen(
          api: api,
          company: 'Synthetic Company',
        ),
      ),
    );
    await tester.tap(find.byTooltip('Find Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample party'));
    await tester.pumpAndSettle();
    for (final option in ['PAY-1 · INR 75', 'INV-1 · INR 100']) {
      final dropdown = find
          .byType(DropdownButtonFormField<String>)
          .at(option.startsWith('PAY') ? 0 : 1);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount to apply'),
      '25',
    );
    await tester.ensureVisible(find.text('Review allocation'));
    await tester.tap(find.text('Review allocation'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('Review allocation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply payment'));
    await tester.pumpAndSettle();
    expect(api.writes, ['Customer/Sample party/PAY-1/INV-1/25/75/100']);
    expect(find.textContaining('Invoice outstanding: INR 75'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
