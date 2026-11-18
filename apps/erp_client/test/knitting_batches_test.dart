import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class BatchApi extends ErpApi {
  BatchApi() : super(Uri.parse('http://localhost:8081'));
  final reads = <Map<String, dynamic>>[];
  Map<String, dynamic>? posted;
  String? version, command;
  bool wrongScope = false;
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => throw StateError('Batch selector must use the bounded register');
  @override
  Future<Map<String, dynamic>> knittingRegister(
    String company,
    String collection, {
    String? job,
    int start = 0,
    String query = '',
    String? state,
    String? productionDate,
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
  }) async {
    reads.add({
      'collection': collection,
      'job': job,
      'start': start,
      'state': state,
    });
    return {
      'version': 1,
      'company': wrongScope ? 'Elsewhere' : company,
      'collection': collection,
      'scope_job': job,
      'page': {
        'start': start,
        'limit': 100,
        'total': 101,
        'has_more': start == 0,
      },
      'rows': collection == 'events'
          ? [
              {
                'name': 'ROLL-DELIVERY',
                'job': job,
                'kind': 'deliver',
                'cancelled': 0,
                'result': {},
              },
              {
                'name': 'BATCH-DELIVERY',
                'job': job,
                'kind': 'deliver_batch',
                'cancelled': 0,
                'result': {
                  'batch': 'BATCH-1',
                  'quantity_kg': '12.345',
                  'roll_count': '3',
                },
              },
              {
                'name': 'CANCELLED',
                'job': job,
                'kind': 'deliver_batch',
                'cancelled': 1,
                'result': {'batch': 'BATCH-1'},
              },
            ]
          : [
              {
                'name': start == 0 ? 'BATCH-1' : 'BATCH-101',
                'job': job,
                'quantity_kg': '-2.345',
                'rolls': '-1',
                'state': 'Awaiting review',
                'source_reference': 'Original stock',
              },
            ],
    };
  }

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    command = action;
    posted = Map.of(values);
    version = modified;
    return {
      'event': 'NEW-EVENT',
      'action': action,
      'data': {
        'quantity_kg': values['quantity_kg'],
        'roll_count': values['rolls'],
      },
    };
  }
}

Future<void> picker(WidgetTester tester, BatchApi api, String entity) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                pickKnitRecord(context, api, 'Mill', entity, job: 'JOB-1'),
            child: const Text('Choose'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Choose'));
  await tester.pumpAndSettle();
}

Future<void> form(
  WidgetTester tester,
  BatchApi api,
  String action,
  Map<String, dynamic> initial,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: KnittingCommandForm(
        api: api,
        workspace: WorkspaceContext.fromJson({
          'company': 'Mill',
          'knitting_enabled': true,
          'capabilities': ['jobs', 'quality', 'delivery'],
        }),
        action: knitActions.firstWhere((a) => a.id == action),
        job: {'name': 'JOB-1', 'modified': 'current-version'},
        initial: initial,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'batch selector preserves negative source counts and bounded paging',
    (tester) async {
      final api = BatchApi();
      addTearDown(api.close);
      await picker(tester, api, 'Batch');
      expect(find.textContaining('-2.345 kg'), findsOneWidget);
      expect(find.textContaining('-1 rolls'), findsOneWidget);
      expect(api.reads.single['job'], 'JOB-1');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(api.reads.last['start'], 100);
      expect(find.textContaining('BATCH-101'), findsOneWidget);
    },
  );
  testWidgets('batch return choices retain exact uncancelled event identity', (
    tester,
  ) async {
    final api = BatchApi();
    addTearDown(api.close);
    await picker(tester, api, 'BatchDelivery');
    expect(find.textContaining('BATCH-DELIVERY'), findsOneWidget);
    expect(find.textContaining('ROLL-DELIVERY'), findsNothing);
    expect(find.textContaining('CANCELLED'), findsNothing);
    expect(find.textContaining('12.345 kg'), findsOneWidget);
  });
  testWidgets('batch selector rejects a response from another company', (
    tester,
  ) async {
    final api = BatchApi()..wrongScope = true;
    addTearDown(api.close);
    await picker(tester, api, 'Batch');
    expect(find.textContaining('unexpected scope'), findsOneWidget);
    expect(find.textContaining('BATCH-1'), findsNothing);
  });
  testWidgets('batch inspection requires an explicit decision', (tester) async {
    final api = BatchApi();
    addTearDown(api.close);
    await form(tester, api, 'review_batch', {
      'batch': 'BATCH-1',
      'remarks': 'Checked',
    });
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an inspection decision.'), findsOneWidget);
    expect(api.posted, isNull);
  });
  testWidgets('negative source batch cannot be released from the form', (
    tester,
  ) async {
    final api = BatchApi();
    addTearDown(api.close);
    await form(tester, api, 'review_batch', {'remarks': 'Checked'});
    await tester.tap(find.text('Choose a record'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Fabric batch'));
    await tester.pumpAndSettle();
    final decision = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Choose a decision',
    );
    await tester.ensureVisible(decision);
    await tester.tap(decision);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Released').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Resolve the original negative stock'),
      findsOneWidget,
    );
    expect(find.text('Confirm & post'), findsNothing);
    expect(api.posted, isNull);
  });
  for (final action in ['deliver_batch', 'return_batch']) {
    testWidgets(
      '$action retains independent weight, count and current job version',
      (tester) async {
        final api = BatchApi();
        addTearDown(api.close);
        await form(tester, api, action, {
          'batch': 'BATCH-1',
          'quantity_kg': '12.345',
          'rolls': '3',
          if (action == 'return_batch') ...{
            'delivery': 'EXACT-DELIVERY',
            'reason': 'Customer returned fabric',
          },
        });
        await tester.tap(find.text('Review entry'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Confirm & post'));
        await tester.tap(find.text('Confirm & post'));
        await tester.pumpAndSettle();
        expect(api.command, action);
        expect(api.version, 'current-version');
        expect(api.posted?['quantity_kg'], '12.345');
        expect(api.posted?['rolls'], '3');
        expect(api.posted?.containsKey('weights_kg'), isFalse);
        expect(find.text('3 rolls'), findsOneWidget);
        if (action == 'return_batch') {
          expect(api.posted?['delivery'], 'EXACT-DELIVERY');
        }
      },
    );
  }
}
