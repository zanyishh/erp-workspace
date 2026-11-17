import 'dart:async';

import 'package:erp_client/bank_statement_matching.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MatchApi extends ErpApi {
  MatchApi() : super(Uri.parse('http://localhost:8081'));
  Completer<Map<String, dynamic>>? pending;
  bool loseResponse = false;
  int writes = 0;
  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String type,
    String query, {
    String? parent,
    String? field,
    Map<String, String>? contextValues,
  }) async => [
    {'value': 'Operating'},
  ];
  @override
  Future<Map<String, dynamic>> bankStatements(
    String company,
    String bank,
    String query,
  ) async => {
    'can_import': false,
    'statements': [
      {
        'name': 'BT-1',
        'date': '2026-11-16',
        'deposit': 100,
        'withdrawal': 0,
        'currency': 'INR',
        'unallocated_amount': '100',
        'description': 'Synthetic statement',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> bankMatches(
    String company,
    String bank,
    String statement, {
    String from = '',
    String to = '',
  }) async => {
    'payments': [
      {
        'name': 'PE-1',
        'date': '2026-11-16',
        'amount': '100',
        'currency': 'INR',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> matchBankPayment(
    String company,
    String account,
    String statement,
    String payment,
    String expectedStatement,
    String expectedPayment, {
    String from = '',
    String to = '',
  }) async {
    writes++;
    if (pending != null) return pending!.future;
    if (loseResponse) throw const ErpException('Response lost');
    return {'matched': '100', 'remaining': '0'};
  }

  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      WorkspaceContext.fromJson({
        'company': company,
        'can_match_bank_statements': true,
      });
}

Future<void> ready(WidgetTester t, MatchApi api) async {
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    BankStatementMatchingScreen(api: api, company: 'Demo'),
              ),
            ),
            child: const Text('Open matching'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open matching'));
  await t.pumpAndSettle();
  await t.tap(find.byTooltip('Find Bank account'));
  await t.pumpAndSettle();
  await t.tap(find.text('Operating'));
  await t.pumpAndSettle();
  await t.tap(find.byType(DropdownButtonFormField<String>).first);
  await t.pumpAndSettle();
  await t.tap(find.textContaining('BT-1').last);
  await t.pumpAndSettle();
  await t.ensureVisible(
    find.widgetWithText(DropdownButtonFormField<String>, 'Posted payment'),
  );
  await t.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'Posted payment'),
  );
  await t.pumpAndSettle();
  await t.tap(find.textContaining('PE-1').last);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Review bank match'));
  await t.tap(find.text('Review bank match'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('bank match prevents leaving during a pending write', (t) async {
    final api = MatchApi()..pending = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await ready(t, api);
    await t.tap(find.text('Match payment'));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(BankStatementMatchingScreen), findsOneWidget);
    api.pending!.complete({'matched': '100', 'remaining': '0'});
    await t.pumpAndSettle();
  });
  testWidgets(
    'an uncertain bank match retains source identifiers for inspection',
    (t) async {
      final api = MatchApi()..loseResponse = true;
      addTearDown(api.close);
      await ready(t, api);
      await t.tap(find.text('Match payment'));
      await t.pumpAndSettle();
      expect(find.text('Check statement record'), findsOneWidget);
      expect(find.textContaining('BT-1 → PE-1'), findsOneWidget);
      expect(api.writes, 1);
    },
  );
  testWidgets('changed bank access removes an open financial review', (
    t,
  ) async {
    final api = MatchApi();
    addTearDown(api.close);
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Demo',
        'access_fingerprint': 'first',
      }),
    );
    await ready(t, api);
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Demo',
        'access_fingerprint': 'second',
      }),
    );
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.writes, 0);
  });
}
