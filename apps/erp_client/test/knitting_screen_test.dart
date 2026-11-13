import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';

void main() {
  testWidgets(
    'operator finds the 201st job through paged search and opens a versioned production entry',
    (tester) async {
      final api = _NavigationApi();
      addTearDown(api.close);
      final access = WorkspaceContext.fromJson({
        'company': 'Demo',
        'knitting_enabled': true,
        'setup_state': 'Active',
        'capabilities': ['jobs', 'production'],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Job 201'), findsNothing);
      await tester.tap(find.text('Find any job'));
      await tester.pumpAndSettle();
      for (var page = 0; page < 4; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(api.offsets, [0, 50, 100, 150, 200]);
      await tester.tap(find.text('Customer 201').first);
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('next-job-action'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.job?['name'], 'Job 201');
      expect(form.job?['modified'], 'current-201');
      expect(form.action.id, 'produce');
      expect(form.initial['programme_line'], 'P1');
      expect(api.writes, 0);
    },
  );

  testWidgets(
    'setup and report shortcuts open role-allowed work with page-specific controls',
    (tester) async {
      final api = _NavigationApi();
      addTearDown(api.close);
      final manager = WorkspaceContext.fromJson({
        'company': 'Demo',
        'knitting_enabled': true,
        'setup_state': 'Active',
        'can_configure': true,
        'capabilities': ['jobs', 'configure', 'reports'],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: manager,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> go(String page) async {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(page).last);
        await tester.pumpAndSettle();
      }

      await go('Setup');
      expect(find.text('Knitting setup'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      await go('Reports');
      expect(find.text('Report options'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      await tester.tap(find.text('Report options'));
      await tester.pumpAndSettle();
      final run = find.text('Run report');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(api.reportRuns, 2);
      expect(find.text('Report options'), findsOneWidget);
    },
  );
  final w = WorkspaceContext.fromJson({
    'company': 'Demo',
    'knitting_enabled': true,
    'capabilities': [
      'jobs',
      'materials',
      'planning',
      'production',
      'quality',
      'delivery',
      'billing',
      'factory',
      'reports',
      'new_job',
      'financial_read',
      'lifecycle',
    ],
  });
  final job = <String, dynamic>{
    'name': 'KN-DEMO-JOB-0001',
    'customer': 'Sample Mills',
    'status': 'Running',
    'target_kg': '88.000',
    'material_mode': 'Customer',
    'programme': [
      {'id': 'P1', 'fabric': 'Single jersey', 'target_kg': '88.000'},
    ],
    'balances': {
      'yarn_kg': '10.000',
      'fabric_kg': '88.000',
      'unbilled_kg': '0.000',
      'loss_kg': '2.000',
      'received_kg': '100.000',
      'produced_kg': '88.000',
      'delivered_kg': '0.000',
      'billed_kg': '0.000',
    },
  };
  final snap = KnittingSnapshot.fromJson({
    'version': 1,
    'company': 'Demo',
    'jobs': [job],
    'rolls': [
      {
        'name': 'ROLL1',
        'job': job['name'],
        'state': 'Awaiting QC',
        'weight_kg': '44.000',
      },
    ],
  });
  testWidgets(
    'job route selects the next eligible step and only unambiguous sources',
    (tester) async {
      tester.view.physicalSize = const Size(390, 930);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selection = <(String, Map<String, dynamic>)>[];
      Future<void> open({
        Map<String, dynamic> balances = const {},
        Map<String, dynamic> workflow = const {},
        WorkspaceContext? access,
        String status = 'Running',
      }) async {
        final current = {
          ...job,
          'status': status,
          'balances': {
            'fabric_kg': '0.000',
            'subcontract_kg': '0.000',
            'yarn_kg': '0.000',
            'unbilled_kg': '0.000',
            ...balances,
          },
          'workflow': {
            'units': '0',
            'open_subcontract': false,
            'remaining_lines': ['P1'],
            ...workflow,
          },
        };
        final source = KnittingSnapshot.fromJson({
          'version': 1,
          'company': 'Demo',
          'jobs': [current],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: Scaffold(
              body: KnittingWorkbench(
                snapshot: source,
                page: 'Jobs',
                selected: current,
                query: '',
                onQuery: (_) {},
                onJob: (_) {},
                onAction: (a, {initial = const {}}) async =>
                    selection.add((a.id, initial)),
                onSource: (_, _) async {},
                workspace: access ?? w,
                onFind: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      final next = find.byKey(const ValueKey('next-job-action'));
      Future<void> choose(String id, Map<String, dynamic> initial) async {
        await Scrollable.ensureVisible(tester.element(next), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(next);
        expect(selection.last.$1, id);
        expect(selection.last.$2, initial);
      }

      await open();
      await choose('receive_yarn', {
        'material_owner': 'Customer',
        'party': 'Sample Mills',
      });
      await open(
        balances: {'yarn_kg': '9.125'},
        workflow: {'only_lot': 'SOURCE-A'},
      );
      await choose('produce', {
        'programme_line': 'P1',
        'inputs': [
          {'lot': 'SOURCE-A'},
        ],
      });
      const mixed = {
        'inspection': {'count': 2, 'only': null},
        'released': {'count': 1, 'only': 'READY-A'},
        'remaining_lines': [],
      };
      await open(workflow: mixed);
      await choose('quality', {});
      await open(
        workflow: mixed,
        access: WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'capabilities': ['jobs', 'delivery'],
        }),
      );
      await choose('deliver', {
        'rolls': ['READY-A'],
      });
      await open(
        workflow: {
          'remaining_lines': [],
          'released': {'count': 2, 'only': null},
        },
      );
      await choose('deliver', {});
      await open(
        balances: {'unbilled_kg': '1.025', 'yarn_kg': '0.750'},
        workflow: {'remaining_lines': [], 'only_delivery': 'PARTIALLY-BILLED'},
      );
      await choose('invoice', {
        'deliveries': ['PARTIALLY-BILLED'],
      });
      await open(
        balances: {'yarn_kg': '0.750'},
        workflow: {'remaining_lines': [], 'only_lot': 'SOURCE-A'},
      );
      await choose('return_yarn', {'lot': 'SOURCE-A'});
      await open(
        workflow: {
          'remaining_lines': [],
          'held': {'count': 1, 'only': 'HELD-A'},
        },
      );
      await choose('quality', {'roll': 'HELD-A'});
      await open(
        workflow: {
          'remaining_lines': [],
          'units': '0',
          'open_subcontract': true,
        },
      );
      expect(next, findsNothing);
      expect(find.text('Subcontract work is open'), findsOneWidget);
      await open(workflow: {'remaining_lines': [], 'units': '2'});
      await choose('adjust_yarn', {'quantity_kg': '0'});
      await open(workflow: {'remaining_lines': []});
      await choose('close_job', {});
      await open(status: 'Completed');
      expect(next, findsNothing);
      expect(find.text('Job complete'), findsOneWidget);
      await open(
        workflow: {
          'inspection': {'count': 1, 'only': 'PRIVATE-ROLL'},
        },
        access: WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'capabilities': ['jobs'],
        }),
      );
      expect(next, findsNothing);
      expect(find.textContaining('Waiting for a colleague'), findsOneWidget);
      expect(find.text('PRIVATE-ROLL'), findsNothing);
    },
  );

  testWidgets(
    'opened job carries its version and single QC source into the real entry',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = TestKnitApi();
      addTearDown(api.close);
      api.publishContext(w);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: w,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OLD-JOB'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('next-job-action')));
      await tester.pumpAndSettle();
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.action.id, 'quality');
      expect(form.job?['name'], 'OLD-JOB');
      expect(form.job?['modified'], '2026-11-13 10:12:00.123456');
      expect(form.initial, {'roll': 'ROLL-A'});
      expect(api.writes, 0);
      expect(find.text('Review entry'), findsOneWidget);
      expect(find.text('Confirm & post'), findsNothing);
    },
  );

  testWidgets(
    'quality queue opens the selected roll with its current job version',
    (tester) async {
      final api = TestKnitApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: w,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quality'));
      await tester.pumpAndSettle();
      final row = find.text('ROLL-A');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.action.id, 'quality');
      expect(form.job?['modified'], '2026-11-13 10:12:00.123456');
      expect(form.initial, {'roll': 'ROLL-A'});
      expect(api.writes, 0);
    },
  );

  testWidgets('factory search matches company machines within an open job', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnittingWorkbench(
            snapshot: KnittingSnapshot('Demo', {
              'machines': [
                {
                  'title': 'Machine North',
                  'capacity_kg': '48',
                  'dia': '12',
                  'gauge': '12',
                  'knit_type': 'Tubular',
                },
                {
                  'title': 'Machine South',
                  'capacity_kg': '48',
                  'dia': '12',
                  'gauge': '12',
                  'knit_type': 'Tubular',
                },
              ],
            }),
            page: 'Factory',
            selected: job,
            query: 'North',
            onQuery: (_) {},
            onJob: (_) {},
            onAction: (_, {initial = const {}}) async {},
            onSource: (_, _) async {},
            workspace: w,
            onFind: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Machine North'), findsOneWidget);
    expect(find.text('Machine South'), findsNothing);
  });

  testWidgets('Done opens the new job after recovery of an uncertain save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _NewJobApi();
    addTearDown(api.close);
    final mill = WorkspaceContext.fromJson({
      'company': 'Demo',
      'knitting_enabled': true,
      'setup_state': 'Active',
      'capabilities': ['jobs', 'new_job', 'materials'],
    });
    api.publishContext(mill);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingScreen(
          api: api,
          workspace: mill,
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New job'));
    await tester.pumpAndSettle();
    final pick = find
        .ancestor(
          of: find.text('Customer').first,
          matching: find.byType(InkWell),
        )
        .first;
    await tester.tap(pick);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic customer'));
    await tester.pumpAndSettle();
    Future<void> enter(Finder field, String value) async {
      await Scrollable.ensureVisible(tester.element(field), alignment: .5);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
    }

    final target = find.widgetWithText(TextFormField, 'Target · kg');
    await enter(target.first, '20');
    final add = find.text('Add fabric programme');
    await Scrollable.ensureVisible(tester.element(add), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await enter(find.widgetWithText(TextFormField, 'Fabric'), 'Rib');
    await enter(target.last, '20');
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check save status'));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(api.readJobs, [null, 'JOB-CREATED']);
    expect(find.text('JOB-CREATED'), findsOneWidget);
    expect(find.text('Receive yarn for the job'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-job-action')), findsOneWidget);
  });

  testWidgets(
    'access refresh retains allowed draft fields and removes private inputs',
    (tester) async {
      final api = TestKnitApi();
      addTearDown(api.close);
      api.publishContext(w);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: w,
            action: knitActions.firstWhere((a) => a.id == 'revise_job'),
            job: {...job, 'name': 'OLD-JOB', 'rate': '123.45'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reason = find.widgetWithText(TextFormField, 'Reason');
      await tester.enterText(reason, 'Keep this operational reason');
      expect(find.widgetWithText(TextFormField, 'Rate per kg'), findsOneWidget);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'access_fingerprint': 'revoked-finance',
          'capabilities': ['jobs', 'lifecycle'],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep this operational reason'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Rate per kg'), findsNothing);
      expect(find.text('Confirm & post'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mill overview uses confirmed output and exact source identities',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = TestKnitApi();
      addTearDown(api.close);
      final mill = WorkspaceContext.fromJson({
        'company': 'Demo',
        'knitting_enabled': true,
        'setup_state': 'Active',
        'capabilities': [
          'overview',
          'jobs',
          'production',
          'quality',
          'delivery',
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: mill,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mill overview'), findsOneWidget);
      expect(find.text('Posted production'), findsOneWidget);
      expect(find.text('Job yarn in store'), findsNothing);
      expect(find.text('Awaiting invoice'), findsNothing);
      await tester.tap(find.byTooltip('View production entries'));
      await tester.pumpAndSettle();
      expect(find.text('PR-007'), findsOneWidget);
      expect(find.text('PR-0071'), findsNothing);
      expect(find.text('PR-CANCELLED'), findsNothing);
      expect(find.text('18.125 kg'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nov 12 · 0.875 kg'));
      await tester.pumpAndSettle();
      expect(find.text('0.875 kg'), findsOneWidget);
      await tester.tap(find.byTooltip('View production entries'));
      await tester.pumpAndSettle();
      expect(find.text('PR-0071'), findsOneWidget);
      expect(find.text('PR-007'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting inspection'));
      await tester.pumpAndSettle();
      expect(find.text('ROLL-A'), findsOneWidget);
      expect(find.text('ROLL-B'), findsNothing);
      await tester.tap(find.byTooltip('Clear queue filter'));
      await tester.pumpAndSettle();
      expect(find.text('ROLL-B'), findsOneWidget);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('View production entries'));
      await tester.pumpAndSettle();
      api.publishContext(mill);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'access_fingerprint': 'jobs-only',
          'capabilities': ['jobs'],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('PR-007'), findsNothing);
      expect(find.text('Production entries'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 834.0, 1440.0]) {
    for (final page in [
      'Jobs',
      'Yarn',
      'Planning',
      'Production',
      'Quality',
      'Delivery',
      'Billing',
      'Factory',
    ]) {
      testWidgets('$page fits $width without overflow', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: KnittingWorkbench(
                  snapshot: snap,
                  page: page,
                  selected: page == 'Jobs' ? null : job,
                  query: '',
                  onQuery: (_) {},
                  onJob: (_) {},
                  onAction: (_, {initial = const {}}) async {},
                  onSource: (_, _) async {},
                  workspace: w,
                  onFind: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('company switch clears job detail and cached amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TestKnitApi();
    await tester.pumpWidget(
      MaterialApp(
        home: KnittingScreen(api: api, workspace: w, onContextChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OLD-JOB'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to jobs'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('OLD-JOB'), findsWidgets);
    final other = WorkspaceContext.fromJson({
      'company': 'Other',
      'knitting_enabled': true,
      'capabilities': ['jobs'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: KnittingScreen(
          api: api,
          workspace: other,
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('OLD-JOB'), findsNothing);
    expect(api.loaded.last, 'Other');
    api.close();
  });
  testWidgets(
    'failed command keeps reviewed input and checks status before retry',
    (tester) async {
      final api = TestKnitApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: w,
            action: knitActions.firstWhere((a) => a.id == 'reopen_job'),
            job: job,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'Correction approved by manager',
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(find.text('Correction approved by manager'), findsOneWidget);
      expect(find.text('Check save status'), findsOneWidget);
      expect(api.writes, 1);
      await tester.tap(find.text('Check save status'));
      await tester.pumpAndSettle();
      expect(find.text('SAVED IN ERP'), findsOneWidget);
      expect(api.writes, 1);
      api.close();
    },
  );
  testWidgets('invoice review shows ERP totals before any write', (
    tester,
  ) async {
    final api = TestKnitApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingCommandForm(
          api: api,
          workspace: w,
          action: knitActions.firstWhere((a) => a.id == 'invoice'),
          job: job,
          initial: const {
            'deliveries': ['DELIVERY-01'],
          },
        ),
      ),
    );
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    expect(find.text('Total to post'), findsOneWidget);
    expect(find.text('8800.00'), findsWidgets);
    expect(api.writes, 0);
    await tester.ensureVisible(find.text('Confirm & post'));
    await tester.tap(find.text('Confirm & post'));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    expect(api.posted?['preview_hash'], 'review-verified');
  });
}

class _NavigationApi extends TestKnitApi {
  final offsets = <int>[];
  int reportRuns = 0;
  Map<String, dynamic> jobRow(int index) => {
    'name': 'Job $index',
    'customer': 'Customer $index',
    'modified': 'current-$index',
    'status': 'Running',
    'programme': [
      {'id': 'P1', 'fabric': 'Interlock', 'target_kg': '20.000'},
    ],
    'target_kg': '20.000',
    'balances': {'yarn_kg': '20.000'},
  };
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {
    'jobs': job == null
        ? [for (var i = 1; i <= 200; i++) jobRow(i)]
        : [jobRow(201)],
  });
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async {
    offsets.add(start);
    return {
      'rows': [
        for (var i = start + 1; i <= start + 50 && i <= 201; i++) jobRow(i),
      ],
      'has_more': start < 200,
    };
  }

  @override
  Future<Map<String, dynamic>> industrySettings(String company) async => {
    'state': 'Active',
    'revision': 1,
    'settings': {
      'warehouse': 'A',
      'service_item': 'Service',
      'fabric_item': 'Fabric',
    },
  };
  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async {
    reportRuns++;
    return {
      'columns': [],
      'rows': [],
      'row_count': 0,
      'summary': {},
      'mode': 'as_of',
      'basis': 'Current stock',
      'start': 0,
      'to_date': '2026-11-13',
      'has_more': false,
    };
  }
}

class TestKnitApi extends ErpApi {
  TestKnitApi() : super(Uri.parse('http://localhost:8081'));
  final loaded = <String>[];
  int writes = 0;
  Map<String, dynamic>? posted;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      contextFor(company!)!;
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async {
    loaded.add(company);
    return KnittingSnapshot.fromJson({
      'version': 1,
      'company': company,
      'events': [
        for (final (id, day, amount, cancelled) in [
          ('PR-007', '2026-11-13', '18.125', 0),
          ('PR-0071', '2026-11-12', '0.875', 0),
          ('PR-CANCELLED', '2026-11-13', '99.000', 1),
        ])
          {
            'name': id,
            'job': 'OLD-JOB',
            'occurred_at': '$day 09:00:00',
            'kind': 'produce',
            'cancelled': cancelled,
            'result': {'quantity_kg': amount},
          },
      ],
      'rolls': [
        for (final (id, state) in [
          ('ROLL-A', 'Awaiting QC'),
          ('ROLL-B', 'Released'),
        ])
          {'name': id, 'state': state, 'weight_kg': '3.000', 'job': 'OLD-JOB'},
      ],
      'jobs': company == 'Demo'
          ? [
              {
                'name': 'OLD-JOB',
                'modified': '2026-11-13 10:12:00.123456',
                'customer': 'Demo customer',
                'status': 'Running',
                'target_kg': '88.000',
                'material_mode': 'Customer',
                'programme': [],
                'balances': {},
              },
            ]
          : [],
    });
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
    posted = values;
    throw const ErpException('Connection interrupted');
  }

  @override
  Future<Map<String, dynamic>> knittingInvoicePreview(
    String company,
    Map<String, dynamic> values,
    String? modified,
  ) async => {
    'currency': 'INR',
    'items': [
      {
        'item': 'Knitting service',
        'quantity': '88.000',
        'uom': 'Kg',
        'rate': '100.00',
        'amount': '8800.00',
      },
    ],
    'net_total': '8800.00',
    'tax_total': '0.00',
    'grand_total': '8800.00',
    'preview_hash': 'review-verified',
  };
  @override
  Future<Map<String, dynamic>> knittingCommandStatus(
    String company,
    String requestId,
  ) async => {
    'event': 'CONFIRMED-EVENT',
    'data': {'job': 'OLD-JOB'},
  };
}

class _NewJobApi extends TestKnitApi {
  final readJobs = <String?>[];
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => {
    'rows': [
      {'name': 'CUSTOMER-X', 'title': 'Synthetic customer'},
    ],
    'has_more': false,
  };
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async {
    readJobs.add(job);
    return KnittingSnapshot(company, {
      'jobs': [
        if (job == 'JOB-CREATED')
          {
            'name': job,
            'customer': 'Synthetic customer',
            'status': 'Running',
            'material_mode': 'Customer',
            'target_kg': '20.000',
            'programme': [
              {'id': 'P1', 'fabric': 'Rib', 'target_kg': '20.000'},
            ],
            'balances': {'yarn_kg': '0.000'},
          },
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> knittingCommandStatus(
    String company,
    String requestId,
  ) async => {
    'event': 'EVENT-CREATED',
    'action': 'create_job',
    'data': {'job': 'JOB-CREATED'},
  };
}
