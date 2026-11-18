import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rowsAction = KnitAction(
  'produce_batches',
  'Record production rows',
  'Production',
  'production',
  [KnitField('entries', 'Production rows', kind: 'batch_rows')],
  needsJob: false,
);
final _workspace = WorkspaceContext.fromJson({
  'company': 'Demo',
  'knitting_enabled': true,
  'capabilities': ['jobs', 'production'],
});
Map<String, dynamic> _row(String job, String line, String kg) => {
  'job': job,
  'modified': 'version-$job',
  'programme_line': line,
  'quantity_kg': kg,
  'rolls': '0',
  'loss_kg': '1.000',
  'inputs': [
    {
      'lot': 'LOT-$job',
      'quantity_kg': '${int.parse(kg.split('.').first) + 1}.000',
      'units': '0',
    },
  ],
  'warehouse': 'MAIN',
  'shift': 'Day',
};

class _RowsApi extends ErpApi {
  _RowsApi() : super(Uri.parse('http://localhost:8081'));
  final posts = <Map<String, dynamic>>[];
  final lookups = <(String, String?)>[];
  Completer<Map<String, dynamic>>? pendingJobs;
  List<Map<String, dynamic>> people = [
    {'name': 'HISTORY-OP-1', 'title': 'Synthetic shopfloor operator'},
  ];
  Map<String, dynamic> sourceJob(String name) => {
    'name': name,
    'modified': 'version-$name',
    'material_mode': 'Customer',
    'source_reference_display': 'Order $name',
    'programme': [
      {
        'id': name == 'J1' ? 'P1' : 'P2',
        'fabric': name == 'J1' ? 'Jersey' : 'Rib',
        'dia': '30',
        'target_kg': '100.000',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async {
    lookups.add((entity, job));
    if (entity == 'Job' && pendingJobs != null) return pendingJobs!.future;
    return {
      'rows': switch (entity) {
        'Job' => [sourceJob('J1'), sourceJob('J2')],
        'ProductionOperator' => people,
        'Lot' => [
          {'name': 'LOT-$job', 'item': 'Synthetic yarn', 'job': job},
        ],
        'Warehouse' => [
          {'name': 'MAIN'},
        ],
        _ => [],
      },
      'has_more': false,
      'start': start,
    };
  }

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {
    'jobs': [sourceJob(job ?? 'J1')],
  });
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posts.add({'action': action, 'values': values, 'modified': modified});
    return {
      'event': 'GROUP-1',
      'action': action,
      'data': {
        'children': [
          {'job': 'J1', 'batch': 'B1', 'event': 'E1'},
          {'job': 'J2', 'batch': 'B2', 'event': 'E2'},
        ],
      },
    };
  }
}

Future<void> _open(
  WidgetTester t,
  _RowsApi api, {
  List<Map<String, dynamic>>? rows,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: KnittingCommandForm(
        api: api,
        workspace: _workspace,
        action: _rowsAction,
        initial: {
          'entries':
              rows ?? [_row('J1', 'P1', '10.000'), _row('J2', 'P2', '20.000')],
        },
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('measured row production is available beside existing roll and batch actions', () {
    expect(knitActions.where((a) => a.id == 'produce_batches'), hasLength(1));
    expect(knitActions.any((a) => a.id == 'produce_bulk'), isTrue);
    expect(knitActions.any((a) => a.id == 'produce_batch'), isTrue);
  });
  test(
    'single batch offers original employee attribution separate from signer',
    () {
      final action = knitActions.firstWhere((a) => a.id == 'produce_batch');
      expect(
        action.fields
            .where((f) => f.key == 'production_operator')
            .map((f) => f.kind),
        ['ProductionOperator'],
      );
    },
  );
  testWidgets('production rows can be reviewed and removed independently', (
    t,
  ) async {
    final api = _RowsApi();
    addTearDown(api.close);
    await _open(t, api);
    expect(find.text('Add production row'), findsOneWidget);
    expect(find.byTooltip('Remove production row 1'), findsOneWidget);
    await t.ensureVisible(find.byTooltip('Remove production row 1'));
    await t.tap(find.byTooltip('Remove production row 1'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Review entry'));
    await t.tap(find.text('Review entry'));
    await t.pumpAndSettle();
    expect(find.textContaining('20.000 kg'), findsWidgets);
    expect(find.textContaining('10.000 kg'), findsNothing);
    await t.ensureVisible(find.text('Confirm & post'));
    await t.tap(find.text('Confirm & post'));
    await t.pumpAndSettle();
    expect(api.posts, hasLength(1));
    expect(api.posts.single['action'], 'produce_batches');
    expect(api.posts.single['values'], {
      'entries': [_row('J2', 'P2', '20.000')],
    });
    expect(api.posts.single['modified'], isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('a mismatched production row is rejected before atomic review', (
    t,
  ) async {
    final api = _RowsApi();
    addTearDown(api.close);
    final bad = _row('J2', 'P2', '20.000');
    bad['loss_kg'] = '1.001';
    await _open(t, api, rows: [_row('J1', 'P1', '10.000'), bad]);
    await t.ensureVisible(find.text('Review entry'));
    await t.tap(find.text('Review entry'));
    await t.pumpAndSettle();
    expect(find.textContaining('Production row 2'), findsWidgets);
    expect(find.text('Confirm & post'), findsNothing);
    expect(api.posts, isEmpty);
  });
  testWidgets(
    'adding a production row opens its own job form without posting',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      await _open(t, api, rows: []);
      await t.ensureVisible(find.text('Add production row'));
      await t.tap(find.text('Add production row'));
      await t.pumpAndSettle();
      expect(find.text('Record batch production'), findsOneWidget);
      expect(find.text('Job'), findsWidgets);
      expect(api.posts, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'preparing an attributed row returns exact local data without a command',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      Map<String, dynamic>? prepared;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  prepared = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KnittingCommandForm(
                        api: api,
                        workspace: _workspace,
                        action: knitActions.firstWhere(
                          (a) => a.id == 'produce_batch',
                        ),
                        prepareOnly: true,
                        initial: {
                          ..._row('J1', 'P1', '10.000'),
                          'production_operator': 'HISTORY-OP-1',
                        }..remove('modified'),
                        initialReferences: {
                          'job': api.sourceJob('J1'),
                          'production_operator': {
                            'name': 'HISTORY-OP-1',
                            'title': 'Synthetic shopfloor operator',
                          },
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open row'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open row'));
      await t.pumpAndSettle();
      expect(find.text('HISTORY-OP-1'), findsNothing);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Synthetic shopfloor operator'), findsOneWidget);
      await t.ensureVisible(find.text('Use production row'));
      await t.tap(find.text('Use production row'));
      await t.pumpAndSettle();
      expect(prepared?['modified'], 'version-J1');
      expect(prepared?['values']['production_operator'], 'HISTORY-OP-1');
      expect(prepared?['values']['quantity_kg'], '10.000');
      expect(prepared?['values']['weights_kg'], isNull);
      expect(api.posts, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'different expected versions of the same job cannot be reviewed together',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      final old = _row('J1', 'P1', '20.000');
      old['modified'] = 'old';
      await _open(t, api, rows: [_row('J1', 'P1', '10.000'), old]);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('different versions across rows'),
        findsOneWidget,
      );
      expect(find.text('Confirm & post'), findsNothing);
    },
  );
  testWidgets(
    'access refresh removes prepared row identities before another review',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      api.publishContext(_workspace);
      await _open(t, api);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'access_fingerprint': 'changed',
          'capabilities': ['jobs', 'production'],
        }),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('10.000 kg'), findsNothing);
      expect(find.textContaining('20.000 kg'), findsNothing);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Add at least one production row.'), findsOneWidget);
      expect(api.posts, isEmpty);
    },
  );

  testWidgets(
    'editing one row job clears its sources and leaves other rows intact',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      await _open(t, api);
      await t.ensureVisible(find.text('Edit row').first);
      await t.tap(find.text('Edit row').first);
      await t.pumpAndSettle();
      final jobPicker = find
          .ancestor(of: find.text('Job'), matching: find.byType(InkWell))
          .first;
      await t.ensureVisible(jobPicker);
      await t.tap(jobPicker);
      await t.pumpAndSettle();
      await t.tap(find.text('Order J2').first);
      await t.pumpAndSettle();
      expect(find.textContaining('LOT-J1'), findsNothing);
      final programme = t.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(programme.initialValue, isNull);
      expect(api.posts, isEmpty);
      await t.tap(find.byType(BackButton).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Leave'));
      await t.pumpAndSettle();
      expect(find.textContaining('10.000 kg'), findsOneWidget);
      expect(find.textContaining('20.000 kg'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('late row job lookup cannot reopen a row after access changes', (
    t,
  ) async {
    final api = _RowsApi();
    addTearDown(api.close);
    api.publishContext(_workspace);
    api.pendingJobs = Completer<Map<String, dynamic>>();
    await _open(t, api);
    await t.ensureVisible(find.text('Edit row').first);
    await t.tap(find.text('Edit row').first);
    await t.pump();
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Demo',
        'knitting_enabled': true,
        'access_fingerprint': 'later',
        'capabilities': ['jobs', 'production'],
      }),
    );
    await t.pumpAndSettle();
    api.pendingJobs!.complete({
      'rows': [api.sourceJob('J1')],
      'has_more': false,
    });
    await t.pumpAndSettle();
    expect(find.text('Record batch production'), findsNothing);
    expect(find.textContaining('10.000 kg'), findsNothing);
    expect(api.posts, isEmpty);
  });
  testWidgets(
    'production rows review and clear stay reachable on a small large-font screen',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(360, 510);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: _rowsAction,
            initial: {
              'entries': [_row('J1', 'P1', '10.000')],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byTooltip('Remove production row 1'));
      await t.tap(find.byTooltip('Remove production row 1'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Add production row'));
      await t.tap(find.text('Add production row'));
      await t.pumpAndSettle();
      expect(find.text('Record batch production'), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(api.posts, isEmpty);
    },
  );
  testWidgets(
    'duplicate original employee names retain distinct saved numbers through review and post',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      api.people = [
        {
          'name': 'PRIVATE-OP-A',
          'title': 'Same saved name',
          'employee_number': '023',
        },
        {
          'name': 'PRIVATE-OP-B',
          'title': 'Same saved name',
          'employee_number': '024',
        },
      ];
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
            initial: {..._row('J1', 'P1', '10.000')}..remove('modified'),
            initialReferences: {'job': api.sourceJob('J1')},
          ),
        ),
      );
      await t.pumpAndSettle();
      final picker = find
          .ancestor(
            of: find.text('Production operator · original employee (optional)'),
            matching: find.byType(InkWell),
          )
          .first;
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pumpAndSettle();
      expect(find.text('Same saved name'), findsNWidgets(2));
      expect(find.text('PRIVATE-OP-A'), findsNothing);
      expect(find.text('PRIVATE-OP-B'), findsNothing);
      expect(find.text('Employee 023'), findsOneWidget);
      expect(find.text('Employee 024'), findsOneWidget);
      await t.tap(find.text('Employee 024'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Same saved name · Employee 024'), findsOneWidget);
      expect(find.text('Recorded by · Administrator'), findsOneWidget);
      await t.ensureVisible(find.text('Confirm & post'));
      await t.tap(find.text('Confirm & post'));
      await t.pumpAndSettle();
      expect(api.posts.single['values']['production_operator'], 'PRIVATE-OP-B');
      expect(api.lookups, contains(('ProductionOperator', 'J1')));
    },
  );

  testWidgets(
    'changing company discards prepared row sources and expected versions',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      await _open(t, api);
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Other',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: _rowsAction,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('10.000 kg'), findsNothing);
      expect(find.textContaining('20.000 kg'), findsNothing);
      expect(find.text('Add production row'), findsOneWidget);
      expect(api.posts, isEmpty);
    },
  );
  testWidgets(
    'numbered original employee choices remain tappable on a small large-font screen',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      api.people = [
        {
          'name': 'PRIVATE-OP-A',
          'title': 'Same saved name',
          'employee_number': '023',
        },
        {
          'name': 'PRIVATE-OP-B',
          'title': 'Same saved name',
          'employee_number': '024',
        },
      ];
      t.view.physicalSize = const Size(360, 510);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
            initial: {..._row('J1', 'P1', '10.000')}..remove('modified'),
            initialReferences: {'job': api.sourceJob('J1')},
          ),
        ),
      );
      await t.pumpAndSettle();
      final picker = find
          .ancestor(
            of: find.text('Production operator · original employee (optional)'),
            matching: find.byType(InkWell),
          )
          .first;
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Employee 024'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Employee 024')),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Employee 024'));
      await t.pumpAndSettle();
      expect(find.text('Same saved name · Employee 024'), findsOneWidget);
      expect(find.text('PRIVATE-OP-B'), findsNothing);
      expect(t.takeException(), isNull);
      expect(api.posts, isEmpty);
    },
  );

  testWidgets(
    'review distinguishes unentered yarn unit count from explicit zero',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      final omitted = _row('J1', 'P1', '10.000');
      (omitted['inputs'] as List).single.remove('units');
      await _open(t, api, rows: [omitted, _row('J2', 'P2', '20.000')]);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.textContaining('bag/cone count not entered'), findsOneWidget);
      expect(find.textContaining('0 bags / cones'), findsOneWidget);
      expect(
        find.textContaining(
          'Whole-lot consumption uses the remaining recorded count',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Job version'), findsNothing);
    },
  );

  testWidgets(
    'removing an earlier row does not move another rows cached job or programme',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      await _open(t, api);
      await t.ensureVisible(find.text('Edit row').last);
      await t.tap(find.text('Edit row').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Use production row'));
      await t.tap(find.text('Use production row'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byTooltip('Remove production row 1'));
      await t.tap(find.byTooltip('Remove production row 1'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Edit row'));
      await t.tap(find.text('Edit row'));
      await t.pumpAndSettle();
      expect(find.textContaining('Order J2'), findsWidgets);
      expect(find.textContaining('Order J1'), findsNothing);
      final programme = t.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(programme.initialValue, 'P2');
      expect(find.textContaining('LOT-J2'), findsWidgets);
      expect(api.posts, isEmpty);
    },
  );
  testWidgets(
    'late lookup errors from a previous company cannot replace current row validation',
    (t) async {
      final api = _RowsApi();
      addTearDown(api.close);
      api.pendingJobs = Completer<Map<String, dynamic>>();
      await _open(t, api);
      await t.ensureVisible(find.text('Edit row').first);
      await t.tap(find.text('Edit row').first);
      await t.pump();
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Other',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: _rowsAction,
          ),
        ),
      );
      await t.pumpAndSettle();
      api.pendingJobs!.completeError(
        const ErpException('Private old company failure'),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Private old company failure'), findsNothing);
      expect(find.textContaining('Company changed.'), findsOneWidget);
      expect(find.text('Record batch production'), findsNothing);
      expect(api.posts, isEmpty);
    },
  );
}
