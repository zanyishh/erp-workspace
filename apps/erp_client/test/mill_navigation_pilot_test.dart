import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/knitting_workspace_layout.dart';
import 'package:erp_client/workspace_context.dart';

class _MillApi extends ErpApi {
  _MillApi() : super(Uri.parse('http://localhost:8081'));
  final acknowledged = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) => acknowledged.future;
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {
    'jobs': [
      {
        'name': 'Pilot job',
        'customer': 'Pilot customer',
        'target_kg': '10',
        'status': 'Running',
        'modified': 'v1',
        'programme': [],
        'balances': {},
      },
    ],
    'rolls': [],
    'events': [],
    'plans': [],
  });
  @override
  Future<Map<String, dynamic>> industrySettings(String company) async => {
    'state': 'Active',
    'settings': {},
    'revision': 1,
  };
}

final _workspace = WorkspaceContext.fromJson({
  'company': 'Pilot mill',
  'setup_state': 'Active',
  'knitting_enabled': true,
  'can_configure': true,
  'capabilities': [
    'overview',
    'jobs',
    'production',
    'materials',
    'delivery',
    'reports',
    'configure',
  ],
});

void main() {
  test('actions that operators choose between have different, task-specific symbols', () {
    for (final ids in [
      [
        'receive_yarn',
        'allocate_yarn',
        'move_yarn',
        'transfer_yarn',
        'repack_yarn',
        'adjust_yarn',
        'return_yarn',
        'subcontract_issue',
        'subcontract_return',
      ],
      [
        'create_machine',
        'create_component',
        'replace_component',
        'component_breakage',
        'issue_consumable',
        'return_consumable',
        'stoppage',
      ],
      [
        'invoice',
        'bill_yarn',
        'credit_invoice',
        'create_estimate',
        'accept_estimate',
        'create_rate',
        'subcontract_bill',
        'create_subcontract',
        'job_from_estimate',
      ],
      [
        'produce',
        'produce_bulk',
        'split_roll',
        'quality',
        'deliver',
        'return_fabric',
        'transfer_fabric',
      ],
    ]) {
      expect(
        ids.map((id) => knitActions.firstWhere((a) => a.id == id).icon).toSet(),
        hasLength(ids.length),
        reason: ids.join(', '),
      );
    }
  });
  testWidgets(
    'General ERP switch is reachable on a short desktop without scrolling the mill rail',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1404, 650);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var opened = false;
      final ws = WorkspaceContext.fromJson({
        'company': 'Pilot mill',
        'knitting_enabled': true,
        'can_configure': true,
        'capabilities': [
          'overview',
          'jobs',
          'materials',
          'planning',
          'production',
          'quality',
          'delivery',
          'billing',
          'factory',
          'reports',
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingWorkspaceLayout(
            workspace: ws,
            page: 'Overview',
            onDestination: (_) {},
            onRecords: () {},
            onGeneral: () => opened = true,
            onAccount: () {},
            actions: const [],
            child: const SizedBox(),
          ),
        ),
      );
      expect(find.text('General ERP').hitTestable(), findsOneWidget);
      await tester.tap(find.text('General ERP'));
      expect(opened, isTrue);
    },
  );
  testWidgets(
    'factory menu hides tasks blocked by native permissions and retains permitted upkeep',
    (tester) async {
      final api = _MillApi();
      addTearDown(api.close);
      final restricted = WorkspaceContext.fromJson({
        'company': 'Pilot mill',
        'setup_state': 'Active',
        'knitting_enabled': true,
        'capabilities': ['factory'],
        'unavailable_knitting_actions': ['create_machine'],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: restricted,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add machine'), findsNothing);
      await tester.tap(find.text('More entries'));
      await tester.pumpAndSettle();
      if (find.text('Install component').evaluate().isEmpty) {
        await tester.tap(find.text('Factory').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Install component'), findsWidgets);
      expect(find.text('Add machine'), findsNothing);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'phone progress follows server acknowledgement (reduced motion $reduced)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _MillApi();
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: KnittingCommandForm(
              api: api,
              workspace: _workspace,
              action: knitActions.firstWhere((a) => a.id == 'deliver'),
              job: {'name': 'Pilot job', 'modified': 'v1'},
              initial: {
                'rolls': ['Roll A'],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder track() => find.byKey(const ValueKey('entry-stage-progress'));
        double value() =>
            tester.widget<LinearProgressIndicator>(track()).value!;
        expect(track(), findsOneWidget);
        expect(value(), closeTo(1 / 3, .001));
        await tester.tap(find.text('Review entry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (!reduced) {
          expect(value(), inExclusiveRange(1 / 3, 2 / 3));
        } else {
          expect(value(), closeTo(2 / 3, .001));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm & post'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(value(), closeTo(2 / 3, .001));
        api.acknowledged.complete({
          'event': 'PILOT-ENTRY',
          'action': 'deliver',
          'data': {'quantity_kg': '10.000'},
        });
        await tester.pumpAndSettle();
        expect(value(), 1);
        expect(find.text('Done'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('phone drawer back leaves the current knitting page open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MillApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingScreen(
          api: api,
          workspace: _workspace,
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Job register'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Mill overview'), findsOneWidget);
  });
  testWidgets(
    'mill menu, visible Back and system Back preserve the workflow and guard changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _MillApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: _workspace,
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Yarn'), findsOneWidget);
      final transition = find.byKey(
        const ValueKey('workspace-destination-transition'),
      );
      double opacity() =>
          tester.widget<FadeTransition>(transition).opacity.value;
      expect(opacity(), 1);
      await tester.tap(find.text('Jobs'));
      await tester.pump();
      expect(opacity(), lessThan(1));
      await tester.pump(const Duration(milliseconds: 65));
      expect(opacity(), inExclusiveRange(.58, 1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.enterText(find.byType(TextField), 'Pilot');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilot job').first);
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsOneWidget);
      expect(find.byTooltip('Back to jobs'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Job register'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Pilot',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Running'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('General ERP').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard setup changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace at sign-in'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to jobs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Job register'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to overview'));
      await tester.pumpAndSettle();
      expect(find.text('Mill overview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
