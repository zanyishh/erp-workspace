import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _workspace = WorkspaceContext.fromJson({
  'company': 'Synthetic Mill',
  'knitting_enabled': true,
  'capabilities': ['jobs', 'lifecycle', 'financial_read'],
});

void main() {
  for (final kind in [
    'imported',
    'empty imported',
    'legacy imported',
    'native',
  ]) {
    testWidgets('generic programme form guards selected $kind job', (
      tester,
    ) async {
      final api = _ProgrammeApi(kind);
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: knitActions.firstWhere((a) => a.id == 'revise_job'),
            initial: const {'reason': 'Synthetic revised specification'},
          ),
        ),
      );
      await tester.tap(find.text('Choose a record'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'SYNTHETIC-JOB'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Review entry'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            )
            .first,
      );
      if (kind != 'native') {
        expect(
          find.textContaining(
            'Full programme revision is unavailable for imported jobs',
          ),
          findsOneWidget,
        );
        expect(find.text('Add fabric programme'), findsNothing);
        expect(button.onPressed, isNull);
        expect(find.text('Confirm & post'), findsNothing);
        expect(api.posts, isEmpty);
      } else {
        expect(button.onPressed, isNotNull);
        await tester.tap(find.text('Review entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm & post'));
        await tester.pumpAndSettle();
        expect(api.posts.single['programme'], [
          {
            'id': 'P1',
            'fabric': 'Synthetic native fabric',
            'target_kg': '10.000',
          },
        ]);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

class _ProgrammeApi extends ErpApi {
  _ProgrammeApi(this.kind) : super(Uri.parse('http://localhost:8081'));
  final String kind;
  final posts = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => {
    'rows': [
      {
        'name': 'SYNTHETIC-JOB',
        'modified': 'v1',
        if (kind != 'legacy imported') 'is_imported': kind != 'native',
        'programme': [
          if (kind != 'empty imported')
            {
              'id': 'P1',
              'fabric': 'Synthetic native fabric',
              'target_kg': '10.000',
              if (kind == 'legacy imported') 'source_fabric_id': '7',
            },
        ],
      },
    ],
    'has_more': false,
  };

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posts.add(values);
    return {'event': 'SYNTHETIC-REVISION', 'data': {}};
  }
}
