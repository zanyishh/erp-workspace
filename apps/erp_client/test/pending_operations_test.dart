import 'package:erp_client/erp_api.dart';
import 'package:erp_client/pending_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecoveryApi extends ErpApi {
  _RecoveryApi() : super(Uri.parse('http://localhost:8081'));
  String state = 'prepared';
  int checks = 0, closes = 0, acknowledged = 0;
  bool hasMore = false;
  Map<String, dynamic> get operation => {
    'request_id': 'test-request-0001',
    'kind': 'invoice',
    'company': 'Synthetic Company',
    'action': 'Save',
    'state': state,
    'creation': '2026-11-16 12:00:00',
    if (state == 'completed') 'result': {'name': 'SINV-RECOVERED'},
  };
  @override
  Future<Map<String, dynamic>> pendingOperations(
    String company, {
    int start = 0,
  }) async {
    if (start > 0) throw const ErpException('Offline');
    return {
      'rows': acknowledged == 0 ? [operation] : [],
      'has_more': hasMore,
    };
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String id,
  ) async {
    checks++;
    return operation;
  }

  @override
  Future<Map<String, dynamic>> closeOperation(String company, String id) async {
    closes++;
    if (state == 'prepared') state = 'closed';
    return operation;
  }

  @override
  Future<void> acknowledgeOperation(String company, String id) async {
    acknowledged++;
  }
}

void main() {
  Future<void> open(WidgetTester t, _RecoveryApi api) async {
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: PendingOperationsScreen(api: api, company: 'Synthetic Company'),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'offline paging retains a recovery action without an unhandled error',
    (t) async {
      final api = _RecoveryApi()..hasMore = true;
      await open(t, api);
      await t.ensureVisible(find.text('Next'));
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pending recovery never replays and prepared is not called failed',
    (t) async {
      final api = _RecoveryApi();
      await open(t, api);
      expect(find.text('Outcome not confirmed'), findsOneWidget);
      expect(api.checks, 0);
      expect(api.closes, 0);
      await t.tap(find.text('Check status'));
      await t.pumpAndSettle();
      expect(api.checks, 1);
      expect(find.text('Outcome not confirmed'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
      await t.tap(find.text('Close unposted request'));
      await t.pumpAndSettle();
      expect(api.closes, 1);
      expect(find.text('Closed without posting'), findsOneWidget);
      await t.tap(find.text('Dismiss'));
      await t.pumpAndSettle();
      expect(api.acknowledged, 1);
      expect(find.text('No operations need attention.'), findsOneWidget);
    },
  );
  testWidgets('a completion arriving before close is shown as completed', (
    t,
  ) async {
    final api = _RecoveryApi();
    await open(t, api);
    api.state = 'completed';
    await t.tap(find.text('Close unposted request'));
    await t.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.textContaining('SINV-RECOVERED'), findsWidgets);
    expect(find.text('Closed without posting'), findsNothing);
    expect(api.acknowledged, 0);
  });
}
