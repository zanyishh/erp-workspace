import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the live job register builds rows on demand and opens the last job',
    (tester) async {
      final jobs = [
        for (int i = 0; i < 200; i++)
          {
            'name': 'TEST-JOB-$i',
            'customer': 'Sample customer',
            'status': 'Running',
            'target_kg': '15.250',
          },
      ];
      final workspace = WorkspaceContext.fromJson({
        'company': 'Sample mill',
        'knitting_enabled': true,
        'capabilities': ['jobs'],
      });
      Map<String, dynamic>? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingWorkbench(
              snapshot: KnittingSnapshot('Sample mill', {'jobs': jobs}),
              workspace: workspace,
              page: 'Jobs',
              selected: null,
              query: '',
              onQuery: (_) {},
              onJob: (job) => opened = job,
              onFind: () {},
              onAction: (_, {initial = const {}}) async {},
              onSource: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TEST-JOB-0'), findsOneWidget);
      expect(find.text('TEST-JOB-199', skipOffstage: false), findsNothing);
      final scrollable = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = find.text('TEST-JOB-199');
      await tester.ensureVisible(last);
      await tester.tap(last);
      expect(opened?['name'], 'TEST-JOB-199');
      expect(find.text('TEST-JOB-0', skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
