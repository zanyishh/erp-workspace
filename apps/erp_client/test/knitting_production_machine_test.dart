import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_reports.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _workspace = WorkspaceContext.fromJson({
  'company': 'Demo',
  'knitting_enabled': true,
  'access_fingerprint': 'initial',
  'capabilities': ['jobs', 'production', 'reports'],
});
final _job = <String, dynamic>{
  'name': 'J1',
  'modified': 'v1',
  'material_mode': 'Customer',
  'programme': [
    {'id': 'P1', 'fabric': 'Jersey', 'dia': '30', 'target_kg': '100.000'},
  ],
};
Map<String, dynamic> _values(String action) => {
  'programme_line': 'P1',
  if (action == 'produce')
    'weights_kg': ['10.000']
  else ...{
    'quantity_kg': '10.000',
    'rolls': '0',
  },
  'inputs': [
    {'lot': 'L1', 'quantity_kg': '11.000', 'units': '0'},
  ],
  'loss_kg': '1.000',
  'shift': 'Day',
  'warehouse': 'MAIN',
};

class _MachineApi extends ErpApi {
  _MachineApi() : super(Uri.parse('http://localhost:8081'));
  final posts = <Map<String, dynamic>>[];
  final lookups = <(String, String?)>[];
  Map<String, dynamic> lastReport = {};
  Completer<Map<String, dynamic>>? pendingMachines;
  Completer<KnittingSnapshot>? pendingSnapshot;
  bool staleCommand = false;
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async {
    lookups.add((entity, job));
    if (entity == 'ProductionMachine' && pendingMachines != null) {
      return pendingMachines!.future;
    }
    return {
      'rows': entity == 'ProductionMachine'
          ? [
              {
                'name': 'PRIVATE-MACHINE-A',
                'title': 'Original Alpha',
                'machine_code': 'DUP',
              },
              {
                'name': 'PRIVATE-MACHINE-B',
                'title': 'Original Beta',
                'machine_code': 'DUP',
              },
            ]
          : entity == 'Job'
          ? [_job]
          : [
              {'name': 'M1', 'title': 'Configured loom'},
            ],
      'start': start,
      'has_more': false,
    };
  }

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async =>
      pendingSnapshot?.future ??
      KnittingSnapshot(company, {
        'jobs': [_job],
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
    if (staleCommand) {
      throw const ErpException('Job changed', staleDocument: true);
    }
    return {
      'event': 'E1',
      'action': action,
      'data': {'batch': 'B1', 'quantity_kg': '10.000', 'roll_count': '0'},
    };
  }

  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async {
    lastReport = Map.from(filters);
    return {
      'columns': [
        {'key': 'production_machine_label', 'label': 'Original machine'},
        {'key': 'production_machine_code', 'label': 'Machine code'},
        {
          'key': 'production_machine_record',
          'label': 'Original machine identity',
        },
      ],
      'rows': [
        {
          'production_machine_label': 'Original Beta',
          'production_machine_code': 'DUP',
          'production_machine_record': 'PRIVATE-MACHINE-B',
        },
      ],
      'summary': {},
      'row_count': 1,
      'start': filters['start'],
      'has_more': filters['start'] == 0,
      'mode': 'as_of',
      'to_date': '2026-11-15',
      'basis': 'Synthetic immutable snapshots',
    };
  }
}

Future<void> _form(
  WidgetTester t,
  _MachineApi api, {
  String action = 'produce_batch',
  Map<String, dynamic>? initial,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: KnittingCommandForm(
        api: api,
        workspace: _workspace,
        action: knitActions.firstWhere((a) => a.id == action),
        job: _job,
        initial: initial ?? _values(action),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _pick(
  WidgetTester t,
  String label,
  String choice, {
  int index = 0,
}) async {
  final field = find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .at(index);
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(choice).first);
  await t.tap(find.text(choice).first);
  await t.pumpAndSettle();
}

void main() {
  test('aggregate and individual production expose separate configured and original machine choices', () {
    for (final id in ['produce_batch', 'produce']) {
      final fields = knitActions.firstWhere((a) => a.id == id).fields;
      expect(
        fields.where((f) => f.key == 'production_machine').map((f) => f.kind),
        ['ProductionMachine'],
      );
      expect(
        fields.any((f) => f.key == 'machine' && f.kind == 'Machine'),
        isTrue,
      );
    }
  });
  testWidgets('two machine identities cannot be reviewed together', (t) async {
    final api = _MachineApi();
    addTearDown(api.close);
    await _form(
      t,
      api,
      initial: {
        ..._values('produce_batch'),
        'machine': 'M1',
        'production_machine': 'PRIVATE-MACHINE-B',
      },
    );
    await t.ensureVisible(find.text('Review entry'));
    await t.tap(find.text('Review entry'));
    await t.pumpAndSettle();
    expect(
      find.textContaining(
        'Choose either a configured machine or an original machine',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirm & post'), findsNothing);
    expect(api.posts, isEmpty);
  });
  for (final action in ['produce_batch', 'produce']) {
    testWidgets(
      '$action preserves original machine identity despite duplicate codes',
      (t) async {
        final api = _MachineApi();
        addTearDown(api.close);
        await _form(
          t,
          api,
          action: action,
          initial: {..._values(action), 'machine': 'M1'},
        );
        await _pick(t, 'Original machine (optional)', 'Original Beta');
        expect(find.text('PRIVATE-MACHINE-B'), findsNothing);
        await t.ensureVisible(find.text('Review entry'));
        await t.tap(find.text('Review entry'));
        await t.pumpAndSettle();
        expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
        await t.ensureVisible(find.text('Confirm & post'));
        await t.tap(find.text('Confirm & post'));
        await t.pumpAndSettle();
        expect(
          api.posts.single['values']['production_machine'],
          'PRIVATE-MACHINE-B',
        );
        expect(api.posts.single['values']['machine'], isNull);
        expect(api.lookups, contains(('ProductionMachine', 'J1')));
      },
    );
  }
  testWidgets(
    'configured machine selection clears preserved machine attribution',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await _form(t, api);
      await _pick(t, 'Original machine (optional)', 'Original Beta');
      await _pick(t, 'Configured machine (optional)', 'Configured loom');
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Confirm & post'));
      await t.tap(find.text('Confirm & post'));
      await t.pumpAndSettle();
      expect(api.posts.single['values']['machine'], 'M1');
      expect(api.posts.single['values']['production_machine'], isNull);
    },
  );
  testWidgets(
    'report filters and groups original machines by identity while showing name and code',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(1440, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Job reconciliation').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Production & loss').last);
      await t.pumpAndSettle();
      expect(find.text('PRIVATE-MACHINE-B'), findsNothing);
      final picker = find.byKey(
        const ValueKey('report-filter-production_machine'),
      );
      expect(picker, findsOneWidget);
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pumpAndSettle();
      await t.tap(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.text('Original Beta'),
            )
            .first,
      );
      await t.pumpAndSettle();
      expect(api.lastReport['production_machine'], isNull);
      final group = find.byKey(const ValueKey('group-production'));
      await t.ensureVisible(group);
      await t.tap(group);
      await t.pumpAndSettle();
      await t.tap(find.text('Original production machine').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Run report'));
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      expect(api.lastReport['production_machine'], 'PRIVATE-MACHINE-B');
      expect(api.lastReport['group_by'], 'production_machine');
      final applied = t.widget<Text>(find.textContaining('Applied:')).data!;
      expect(applied, contains('Group records: Original production machine'));
      expect(applied, isNot(contains('production_machine')));
      expect(
        t.widget<Text>(find.textContaining('Applied:')).data,
        contains('Original Beta · Machine DUP'),
      );
      expect(find.text('PRIVATE-MACHINE-B'), findsNothing);
      final native = find.byKey(const ValueKey('report-filter-machine'));
      await t.ensureVisible(native);
      await t.enterText(native, 'M1');
      await t.ensureVisible(find.text('Next'));
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(api.lastReport['production_machine'], 'PRIVATE-MACHINE-B');
      await t.ensureVisible(find.text('Run report'));
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      expect(api.lastReport['production_machine'], isNull);
      expect(api.lastReport['machine'], 'M1');
    },
  );
  testWidgets(
    'bulk production keeps each original machine in its own measured-roll row',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await _form(
        t,
        api,
        action: 'produce_bulk',
        initial: {
          'entries': [
            {..._values('produce'), 'machine': 'M1'},
            {..._values('produce'), 'machine': 'M1'},
          ],
        },
      );
      await _pick(t, 'Original machine (optional)', 'Original Alpha');
      await _pick(t, 'Original machine (optional)', 'Original Beta', index: 1);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Original Alpha · Machine DUP'), findsOneWidget);
      expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
      await t.ensureVisible(find.text('Confirm & post'));
      await t.tap(find.text('Confirm & post'));
      await t.pumpAndSettle();
      final rows = api.posts.single['values']['entries'] as List;
      expect(rows.map((row) => row['production_machine']), [
        'PRIVATE-MACHINE-A',
        'PRIVATE-MACHINE-B',
      ]);
      for (final row in rows) {
        expect(row['machine'], isNull);
        expect(row['weights_kg'], ['10.000']);
      }
    },
  );
  testWidgets(
    'prepared batch rows retain original machine name code and opaque request identity',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: knitActions.firstWhere((a) => a.id == 'produce_batches'),
            initial: {
              'entries': [
                {'job': 'J1', 'modified': 'v1', ..._values('produce_batch')},
              ],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Edit row'));
      await t.tap(find.text('Edit row'));
      await t.pumpAndSettle();
      await _pick(t, 'Original machine (optional)', 'Original Beta');
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Use production row'));
      await t.tap(find.text('Use production row'));
      await t.pumpAndSettle();
      expect(
        find.text('Original machine · Original Beta · Machine DUP'),
        findsOneWidget,
      );
      expect(api.posts, isEmpty);
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Confirm & post'));
      await t.tap(find.text('Confirm & post'));
      await t.pumpAndSettle();
      expect(api.posts.single['action'], 'produce_batches');
      expect(
        (api.posts.single['values']['entries'] as List)
            .single['production_machine'],
        'PRIVATE-MACHINE-B',
      );
    },
  );
  testWidgets(
    'company changes discard an existing original machine selection',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await _form(t, api);
      await _pick(t, 'Original machine (optional)', 'Original Beta');
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Other',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
            job: {..._job, 'name': 'OTHER-JOB'},
            initial: _values('produce_batch'),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Original Beta · Machine DUP'), findsNothing);
      expect(api.posts, isEmpty);
    },
  );
  testWidgets(
    'original machine picker remains usable on small enlarged-text screen',
    (t) async {
      final api = _MachineApi();
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
            action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
            job: _job,
            initial: _values('produce_batch'),
          ),
        ),
      );
      await t.pumpAndSettle();
      final picker = find
          .ancestor(
            of: find.text('Original machine (optional)'),
            matching: find.byType(InkWell),
          )
          .first;
      await t.ensureVisible(picker);
      await t.pumpAndSettle();
      await t.tap(picker);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Original Beta'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Original Beta')),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Original Beta'));
      await t.pumpAndSettle();
      expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(api.posts, isEmpty);
    },
  );

  test('machine labels preserve leading-zero codes and do not invent missing codes', () {
    expect(
      knittingProductionMachineTitle({
        'title': 'Saved loom',
        'machine_code': '007',
      }),
      'Saved loom · Machine 007',
    );
    expect(
      knittingProductionMachineTitle({
        'title': 'Saved loom',
        'machine_code': '',
      }),
      'Saved loom',
    );
  });
  testWidgets(
    'an old machine picker result cannot restore attribution after access refresh',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      api.publishContext(_workspace);
      api.pendingMachines = Completer<Map<String, dynamic>>();
      await _form(t, api);
      final picker = find
          .ancestor(
            of: find.text('Original machine (optional)'),
            matching: find.byType(InkWell),
          )
          .first;
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pump();
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'access_fingerprint': 'changed',
          'capabilities': ['jobs', 'production', 'reports'],
        }),
      );
      await t.pump();
      api.pendingMachines!.complete({
        'rows': [
          {
            'name': 'PRIVATE-MACHINE-B',
            'title': 'Original Beta',
            'machine_code': 'DUP',
          },
        ],
        'start': 0,
        'has_more': false,
      });
      await t.pumpAndSettle();
      await t.tap(find.text('Original Beta'));
      await t.pumpAndSettle();
      expect(find.text('Original Beta · Machine DUP'), findsNothing);
      expect(api.posts, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'clearing an original machine keeps the attribution absent from the reviewed payload',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await _form(t, api);
      await _pick(t, 'Original machine (optional)', 'Original Beta');
      final selected = find.text('Original Beta · Machine DUP');
      final field = find
          .ancestor(of: selected, matching: find.byType(FormField<dynamic>))
          .first;
      final clear = find.descendant(
        of: field,
        matching: find.text('Clear selection'),
      );
      await t.ensureVisible(clear);
      await t.tap(clear);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Confirm & post'));
      await t.tap(find.text('Confirm & post'));
      await t.pumpAndSettle();
      expect(api.posts.single['values']['production_machine'], isNull);
      expect(api.posts.single['values']['machine'], isNull);
    },
  );
  testWidgets(
    'company-level production row validation rejects both machine kinds',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: knitActions.firstWhere((a) => a.id == 'produce_batches'),
            initial: {
              'entries': [
                {
                  'job': 'J1',
                  'modified': 'v1',
                  ..._values('produce_batch'),
                  'machine': 'M1',
                  'production_machine': 'PRIVATE-MACHINE-B',
                },
              ],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Review entry'));
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Choose either a configured machine or an original machine',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm & post'), findsNothing);
      expect(api.posts, isEmpty);
    },
  );
  for (final replacement in ['api', 'job']) {
    testWidgets(
      'old report machine picker cannot populate a replaced $replacement scope',
      (t) async {
        final old = _MachineApi(), fresh = _MachineApi();
        addTearDown(old.close);
        addTearDown(fresh.close);
        t.view.physicalSize = const Size(1440, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var selectedApi = old;
        var selectedJob = 'J1';
        late StateSetter rebuild;
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                rebuild = set;
                return Scaffold(
                  body: KnittingReports(
                    api: selectedApi,
                    company: 'Demo',
                    financialRead: false,
                    job: selectedJob,
                  ),
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Job reconciliation').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Production & loss').last);
        await t.pumpAndSettle();
        old.pendingMachines = Completer<Map<String, dynamic>>();
        final picker = find.byKey(
          const ValueKey('report-filter-production_machine'),
        );
        await t.ensureVisible(picker);
        await t.tap(picker);
        await t.pump();
        rebuild(() {
          if (replacement == 'api') {
            selectedApi = fresh;
          } else {
            selectedJob = 'J2';
          }
        });
        await t.pump();
        old.pendingMachines!.complete({
          'rows': [
            {
              'name': 'PRIVATE-OLD-SESSION-MACHINE',
              'title': 'Old session machine',
              'machine_code': '001',
            },
          ],
          'start': 0,
          'has_more': false,
        });
        await t.pumpAndSettle();
        await t.tap(find.text('Old session machine'));
        await t.pumpAndSettle();
        expect(find.text('Old session machine · Machine 001'), findsNothing);
        await t.ensureVisible(find.text('Run report'));
        await t.tap(find.text('Run report'));
        await t.pumpAndSettle();
        expect(selectedApi.lastReport['production_machine'], isNull);
        expect(selectedApi.lastReport['job'], selectedJob);
      },
    );
  }
  testWidgets(
    'fixed job name replacement clears production attribution and quantities',
    (t) async {
      final api = _MachineApi();
      addTearDown(api.close);
      var selectedJob = _job;
      late StateSetter rebuild;
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              rebuild = set;
              return KnittingCommandForm(
                api: api,
                workspace: _workspace,
                action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
                job: selectedJob,
                initial: _values('produce_batch'),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await _pick(t, 'Original machine (optional)', 'Original Beta');
      rebuild(() => selectedJob = {..._job, 'name': 'J2', 'modified': 'v2'});
      await t.pumpAndSettle();
      expect(find.text('Original Beta · Machine DUP'), findsNothing);
      expect(find.widgetWithText(TextFormField, '10.000'), findsNothing);
      expect(find.textContaining('J2'), findsWidgets);
      expect(api.posts, isEmpty);
    },
  );
  testWidgets('same fixed job refresh preserves production draft selections', (
    t,
  ) async {
    final api = _MachineApi();
    addTearDown(api.close);
    var selectedJob = _job;
    late StateSetter rebuild;
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            rebuild = set;
            return KnittingCommandForm(
              api: api,
              workspace: _workspace,
              action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
              job: selectedJob,
              initial: _values('produce_batch'),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await _pick(t, 'Original machine (optional)', 'Original Beta');
    rebuild(() => selectedJob = {..._job, 'modified': 'v2'});
    await t.pumpAndSettle();
    expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '10.000'), findsOneWidget);
    expect(api.posts, isEmpty);
  });
  for (final replacement in ['api', 'company', 'job']) {
    testWidgets(
      'pending stale production reload cannot overwrite new $replacement selections',
      (t) async {
        final old = _MachineApi()..staleCommand = true;
        final fresh = _MachineApi();
        addTearDown(old.close);
        addTearDown(fresh.close);
        var selectedApi = old;
        var selectedWorkspace = _workspace;
        var selectedJob = _job;
        late StateSetter rebuild;
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                rebuild = set;
                return KnittingCommandForm(
                  api: selectedApi,
                  workspace: selectedWorkspace,
                  action: knitActions.firstWhere(
                    (a) => a.id == 'produce_batch',
                  ),
                  job: selectedJob,
                  initial: _values('produce_batch'),
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Review entry'));
        await t.tap(find.text('Review entry'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Confirm & post'));
        await t.tap(find.text('Confirm & post'));
        await t.pumpAndSettle();
        old.pendingSnapshot = Completer<KnittingSnapshot>();
        await t.tap(find.text('Reload current sources'));
        await t.pump();
        rebuild(() {
          if (replacement == 'api') selectedApi = fresh;
          if (replacement == 'job') {
            selectedJob = {..._job, 'name': 'J2', 'modified': 'v2'};
          }
          if (replacement == 'company') {
            selectedWorkspace = WorkspaceContext.fromJson({
              'company': 'Other',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production', 'reports'],
            });
          }
        });
        await t.pumpAndSettle();
        await _pick(t, 'Original machine (optional)', 'Original Beta');
        old.pendingSnapshot!.complete(
          KnittingSnapshot('Demo', {
            'jobs': [
              {..._job, 'modified': 'OLD-VERSION'},
            ],
          }),
        );
        await t.pumpAndSettle();
        expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
        expect(find.textContaining('Current sources loaded.'), findsNothing);
        expect(find.text('Review entry'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final screen in ['form', 'report']) {
    testWidgets(
      'replaced $screen API revocation hides current production content',
      (t) async {
        final old = _MachineApi(), fresh = _MachineApi();
        addTearDown(old.close);
        addTearDown(fresh.close);
        old.publishContext(_workspace);
        fresh.publishContext(_workspace);
        var selectedApi = old;
        late StateSetter rebuild;
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                rebuild = set;
                return screen == 'form'
                    ? KnittingCommandForm(
                        api: selectedApi,
                        workspace: _workspace,
                        action: knitActions.firstWhere(
                          (a) => a.id == 'produce_batch',
                        ),
                        job: _job,
                        initial: _values('produce_batch'),
                      )
                    : Scaffold(
                        body: KnittingReports(
                          api: selectedApi,
                          company: 'Demo',
                          financialRead: false,
                        ),
                      );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        rebuild(() => selectedApi = fresh);
        await t.pumpAndSettle();
        fresh.publishContext(
          WorkspaceContext.fromJson({
            'company': 'Demo',
            'knitting_enabled': true,
            'access_fingerprint': 'revoked',
            'capabilities': ['jobs'],
          }),
        );
        await t.pumpAndSettle();
        expect(
          find.text(screen == 'form' ? 'Review entry' : 'Run report'),
          findsNothing,
        );
        expect(
          find.textContaining(
            screen == 'form'
                ? 'Your access to this action changed.'
                : 'Your access to these reports changed.',
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final replacement in ['api', 'company', 'job']) {
    testWidgets(
      'pending access revalidation cannot replace a new production $replacement context',
      (t) async {
        final old = _MachineApi(), fresh = _MachineApi();
        addTearDown(old.close);
        addTearDown(fresh.close);
        old.publishContext(_workspace);
        fresh.publishContext(_workspace);
        var selectedApi = old;
        var selectedWorkspace = _workspace;
        var selectedJob = _job;
        late StateSetter rebuild;
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                rebuild = set;
                return KnittingCommandForm(
                  api: selectedApi,
                  workspace: selectedWorkspace,
                  action: knitActions.firstWhere(
                    (a) => a.id == 'produce_batch',
                  ),
                  job: selectedJob,
                  initial: _values('produce_batch'),
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        old.pendingSnapshot = Completer<KnittingSnapshot>();
        old.publishContext(
          WorkspaceContext.fromJson({
            'company': 'Demo',
            'knitting_enabled': true,
            'access_fingerprint': 'refresh',
            'capabilities': ['jobs', 'production', 'reports'],
          }),
        );
        await t.pump();
        rebuild(() {
          if (replacement == 'api') {
            selectedApi = fresh;
          }
          if (replacement == 'company') {
            selectedWorkspace = WorkspaceContext.fromJson({
              'company': 'Other',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production', 'reports'],
            });
          }
          if (replacement == 'job') {
            selectedJob = {..._job, 'name': 'J2', 'modified': 'v2'};
          }
        });
        await t.pumpAndSettle();
        old.pendingSnapshot!.complete(
          KnittingSnapshot('Demo', {
            'jobs': [
              {..._job, 'modified': 'OLD'},
            ],
          }),
        );
        await t.pumpAndSettle();
        expect(find.textContaining('Access refreshed.'), findsNothing);
        if (replacement == 'job') {
          expect(find.textContaining('J2'), findsWidgets);
        }
        await _pick(t, 'Original machine (optional)', 'Original Beta');
        expect(find.text('Original Beta · Machine DUP'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
