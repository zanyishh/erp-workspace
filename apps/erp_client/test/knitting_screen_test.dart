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
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async {
    loaded.add(company);
    return KnittingSnapshot.fromJson({
      'version': 1,
      'company': company,
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
