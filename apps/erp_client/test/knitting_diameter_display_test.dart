import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final access = WorkspaceContext.fromJson({
  'company': 'Synthetic Mill',
  'knitting_enabled': true,
  'capabilities': ['jobs', 'lifecycle'],
});

Map<String, dynamic> job(Map<String, dynamic> diameter) => {
  'name': 'SYNTHETIC-JOB',
  'modified': 'current-version',
  'customer': 'Synthetic customer',
  'status': 'Running',
  'programme': [
    {
      'id': 'P1',
      'fabric': 'Single jersey',
      'colour': 'Natural',
      'gauge': '18',
      'knit_type': 'Tubular',
      'target_kg': '10.000',
      ...diameter,
    },
  ],
};

class RevisionApi extends ErpApi {
  RevisionApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic>? posted;
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posted = values;
    throw const ErpException(
      'The imported programme requires source review.',
      validationRejected: true,
    );
  }
}

void main() {
  for (final (name, diameter, shown) in [
    ('native', {'dia': '15'}, '15'),
    (
      'imported',
      {'dia': '15', 'dia_display': '38', 'dia_basis': 'source_master_id'},
      '38',
    ),
    (
      'unresolved',
      {'dia': '15', 'dia_display': null, 'dia_basis': 'unresolved'},
      '—',
    ),
    (
      'unrecorded',
      {'dia': '15', 'dia_display': '', 'dia_basis': 'unrecorded'},
      '—',
    ),
  ]) {
    testWidgets(
      '$name programme shows its measured diameter without converting source IDs',
      (tester) async {
        final record = job(diameter);
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: Scaffold(
              body: KnittingWorkbench(
                snapshot: KnittingSnapshot('Synthetic Mill', {
                  'jobs': [record],
                }),
                page: 'Jobs',
                selected: record,
                query: '',
                workspace: access,
                onQuery: (_) {},
                onJob: (_) {},
                onFind: () {},
                onAction: (_, {initial = const {}}) async {},
                onSource: (_, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Fabric programme'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Natural · $shown dia / 18 G'), findsOneWidget);
        expect((record['programme'] as List).single['dia'], '15');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'imported revision protects source dimensions before any submission',
    (tester) async {
      final api = RevisionApi();
      addTearDown(api.close);
      final record = job({
        'dia': '15',
        'dia_display': '38',
        'dia_basis': 'source_master_id',
        'source_fabric_id': '101',
        'source_size_id': '202',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: access,
            action: knitActions.firstWhere((a) => a.id == 'revise_job'),
            job: record,
            initial: const {'reason': 'Review retained source fields'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original programme protected'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Dia'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Review entry'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(api.posted, isNull);
      final preserved = (record['programme'] as List).single as Map;
      expect(preserved['dia'], '15');
      expect(preserved['dia_display'], '38');
      expect(preserved['source_fabric_id'], '101');
      expect(preserved['source_size_id'], '202');
      expect(find.text('Confirm & post'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native revision edits the physical diameter without stale projection fields',
    (tester) async {
      final api = RevisionApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: access,
            action: knitActions.firstWhere((a) => a.id == 'revise_job'),
            job: job({
              'dia': '15',
              'dia_display': '15',
              'dia_basis': 'physical',
            }),
            initial: const {'reason': 'Update measured diameter'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextFormField, 'Dia');
      await tester.ensureVisible(input);
      await tester.enterText(input, '16');
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('16'), findsOneWidget);
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      final sent = (api.posted!['programme'] as List).single as Map;
      expect(sent['dia'], '16');
      expect(sent.containsKey('dia_display'), isFalse);
      expect(sent.containsKey('dia_basis'), isFalse);
    },
  );

  testWidgets(
    'programme selectors use the displayed diameter and retain line identity',
    (tester) async {
      final api = RevisionApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Synthetic Mill',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: knitActions.firstWhere((a) => a.id == 'produce'),
            job: job({
              'dia': '15',
              'dia_display': '38',
              'dia_basis': 'source_master_id',
            }),
            initial: const {'programme_line': 'P1'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('38 dia'), findsWidgets);
      final line = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(line.initialValue, 'P1');
    },
  );
}
