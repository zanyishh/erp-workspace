import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/pending_operations.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _operation(String company, {String state = 'prepared'}) =>
    {
      'request_id': 'architecture-operation-0001',
      'company': company,
      'kind': 'invoice',
      'action': 'Save',
      'state': state,
      'creation': '2026-11-16 12:00:00',
    };

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://localhost:8081'));
  Future<Map<String, dynamic>> Function(String)? read;
  final status = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> pendingOperations(
    String company, {
    int start = 0,
  }) async =>
      read?.call(company) ??
      {
        'rows': [_operation(company)],
        'has_more': false,
      };
  @override
  Future<Map<String, dynamic>> operationStatus(String company, String id) =>
      status.future;
}

void main() {
  Future<void> show(WidgetTester tester, _Api api, String company) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PendingOperationsScreen(api: api, company: company),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'refresh during a status check does not leave the operation permanently busy',
    (tester) async {
      final api = _Api();
      addTearDown(api.close);
      await show(tester, api, 'Synthetic');
      await tester.tap(find.text('Check status'));
      await tester.pump();
      await tester.tap(find.byTooltip('Refresh pending operations'));
      await tester.pump();
      api.status.complete(_operation('Synthetic', state: 'closed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Check status'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pending old-company access refresh cannot hide new pending operations',
    (tester) async {
      final api = _Api();
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Old company',
          'access_fingerprint': 'one',
        }),
      );
      await show(tester, api, 'Old company');
      final pending = Completer<Map<String, dynamic>>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete({
            'rows': [_operation('Old company')],
            'has_more': false,
          });
        }
      });
      api.read = (company) => company == 'Old company'
          ? pending.future
          : Future.value({
              'rows': [_operation(company)],
              'has_more': false,
            });
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Old company',
          'access_fingerprint': 'two',
          'revision': 1,
        }),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: PendingOperationsScreen(api: api, company: 'New company'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New company'), findsOneWidget);
      expect(find.text('Refreshing your access…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
