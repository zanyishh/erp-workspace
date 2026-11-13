import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';

void main() {
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
                  onBack: () {},
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
    expect(find.text('All jobs'), findsOneWidget);
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
