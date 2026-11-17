import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';

import 'knitting_confirmation_test.dart' show ConfirmationApi;

class _RecoveryApi extends ConfirmationApi {
  String state = 'prepared';
  int writes = 0, acknowledged = 0;
  Completer<Map<String, dynamic>>? preparing;
  @override
  bool supportsOperationRecovery(String company) => true;
  Map<String, dynamic> get operation => {
    'state': state,
    if (state == 'completed')
      'result': {
        'event': 'EVT-RECOVERED',
        'action': 'return_yarn',
        'data': {'quantity_kg': '16.000'},
      },
  };
  @override
  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String id, {
    String? doctype,
    String? name,
    String? action,
  }) async => preparing == null ? operation : await preparing!.future;
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

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    writes++;
    throw const ErpException('Response interrupted');
  }
}

void main() {
  testWidgets(
    'a changed knitting job cannot dispatch an older prepared entry',
    (t) async {
      final api = _RecoveryApi()..preparing = Completer<Map<String, dynamic>>();
      final job = ValueNotifier('JOB-1');
      addTearDown(api.close);
      addTearDown(job.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: job,
            builder: (_, value, _) => KnittingCommandForm(
              api: api,
              workspace: WorkspaceContext.fromJson({
                'company': 'Demo',
                'knitting_enabled': true,
                'capabilities': ['materials'],
              }),
              action: knitActions.firstWhere(
                (a) => a.id == 'return_yarn' && a.needsJob,
              ),
              job: {'name': value, 'modified': value},
              initial: {'lot': 'LOT-1', 'quantity_kg': '16'},
            ),
          ),
        ),
      );
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm & post'));
      await t.pump();
      job.value = 'JOB-2';
      await t.pumpAndSettle();
      api.preparing!.complete({'state': 'prepared'});
      await t.pumpAndSettle();
      expect(api.writes, 0);
      expect(find.text('Review entry'), findsOneWidget);
    },
  );
  Future<void> open(WidgetTester t, _RecoveryApi api) async {
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: KnittingCommandForm(
          api: api,
          workspace: WorkspaceContext.fromJson({
            'company': 'Demo',
            'knitting_enabled': true,
            'capabilities': ['materials'],
          }),
          action: knitActions.firstWhere(
            (a) => a.id == 'return_yarn' && a.needsJob,
          ),
          job: {'name': 'JOB-1', 'modified': 'now'},
          initial: {'lot': 'LOT-1', 'quantity_kg': '16'},
        ),
      ),
    );
    await t.tap(find.text('Review entry'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirm & post'));
    await t.pumpAndSettle();
  }

  testWidgets('knitting uncertain request stays locked until explicit close', (
    t,
  ) async {
    final api = _RecoveryApi();
    await open(t, api);
    await t.tap(find.text('Check save status'));
    await t.pumpAndSettle();
    expect(find.text('Edit entry'), findsNothing);
    expect(find.text('Done'), findsNothing);
    expect(api.writes, 1);
    await t.tap(find.text('Close unposted request'));
    await t.pumpAndSettle();
    expect(find.text('Review entry'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(api.writes, 1);
  });
  testWidgets('knitting recovers the original event without another posting', (
    t,
  ) async {
    final api = _RecoveryApi();
    await open(t, api);
    api.state = 'completed';
    await t.tap(find.text('Check save status'));
    await t.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(api.writes, 1);
    expect(api.acknowledged, 1);
  });
}
