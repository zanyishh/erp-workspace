import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const company = 'Synthetic Knitting Company';
final workspace = WorkspaceContext.fromJson({
  'company': company,
  'knitting_enabled': true,
  'can_read_imported_history': true,
  'setup_state': 'Active',
  'capabilities': [
    'overview',
    'jobs',
    'materials',
    'production',
    'quality',
    'delivery',
    'billing',
  ],
});

class PresentationApi extends ErpApi {
  PresentationApi() : super(Uri.parse('http://localhost:8081'));
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {
    'jobs': [
      {
        'name': 'SYNTHETIC-JOB',
        'source_reference': 'ORDER-487',
        'customer': 'Synthetic customer',
        'status': 'Running',
        'job_date': '2026-11-14',
        'due_date': '2026-11-21',
        'target_kg': '178.200',
        'programme': [],
        'balances': {},
      },
    ],
    'events': [],
    'rolls': [],
  });
}

void main() {
  for (final width in [390.0, 834.0, 1440.0]) {
    testWidgets('company is visible and switchable above content at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PresentationApi();
      addTearDown(api.close);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: workspace,
            onContextChanged: (_) {},
            onCompany: () => changes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.text(company);
      expect(find.textContaining(company), findsOneWidget);
      expect(find.text('Mill overview'), findsOneWidget);
      expect(selector, findsOneWidget);
      expect(tester.getTopLeft(selector).dy, lessThan(200));
      await tester.tap(selector);
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'original production remains reachable when new production is empty',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PresentationApi();
      addTearDown(api.close);
      final opened = <String>[];
      Future<void> render({bool history = true}) => tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: workspace,
            onContextChanged: (_) {},
            onHistory: history ? opened.add : null,
          ),
        ),
      );
      await render();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original production records'));
      expect(opened, ['production']);
      expect(
        find.text('No in-house production in the loaded postings.'),
        findsOneWidget,
      );
      await render(history: false);
      await tester.pumpAndSettle();
      expect(find.text('Original production records'), findsNothing);
    },
  );

  testWidgets('module original-record links preserve family', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PresentationApi();
    addTearDown(api.close);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingScreen(
          api: api,
          workspace: workspace,
          onContextChanged: (_) {},
          onHistory: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (page, label, family) in [
      ('Yarn', 'Original yarn receipts', 'yarn_receipt'),
      ('Production', 'Original production', 'production'),
      ('Delivery', 'Original deliveries', 'delivery'),
      ('Billing', 'Original invoices', 'invoice'),
      ('Jobs', 'Original orders', 'job'),
    ]) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      expect(opened.last, family);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('job detail distinguishes original order date from due date', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PresentationApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingScreen(
          api: api,
          workspace: workspace,
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ORDER-487'));
    await tester.pumpAndSettle();
    expect(find.text('Order date 2026-11-14'), findsOneWidget);
    expect(find.text('Due 2026-11-21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
