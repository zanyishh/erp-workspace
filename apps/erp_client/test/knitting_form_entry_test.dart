import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'fabric specifications are readable in entry and review at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = ErpApi(Uri.parse('http://localhost:8081'));
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: KnittingCommandForm(
              api: api,
              workspace: WorkspaceContext.fromJson({
                'company': 'Sample Textiles',
                'knitting_enabled': true,
                'capabilities': ['jobs', 'lifecycle'],
              }),
              action: knitActions.firstWhere((a) => a.id == 'revise_job'),
              job: {
                'name': 'JOB-01',
                'customer': 'Sample Mill',
                'programme': [
                  {
                    'id': 'P1348294535944',
                    'fabric': 'Interlock',
                    'colour': 'Indigo',
                    'target_kg': '45.000',
                    'gsm': ['180', '200'],
                    'll': ['2.7'],
                    'knit_type': 'Tubular',
                  },
                ],
              },
              initial: const {'reason': 'Customer revised the specification'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('P1348294535944'), findsNothing);
        expect(find.textContaining('Sample Mill'), findsWidgets);
        final gsm = find.widgetWithText(TextFormField, 'GSM · up to 2 values');
        await tester.ensureVisible(gsm);
        await tester.enterText(gsm, '180, 200, 210');
        await tester.tap(find.text('Review entry'));
        await tester.pumpAndSettle();
        expect(find.textContaining('at most 2'), findsOneWidget);
        await tester.enterText(gsm, '180, 200');
        await tester.tap(find.text('Review entry'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm & post'), findsOneWidget);
        expect(find.textContaining('P1348294535944'), findsNothing);
        expect(find.textContaining('Interlock'), findsWidgets);
        expect(find.textContaining('180, 200'), findsWidgets);
        expect(find.textContaining('Indigo'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('back immediately after typing protects the knitting draft', (
    tester,
  ) async {
    final api = _SourceApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => KnittingCommandForm(
                    api: api,
                    workspace: WorkspaceContext.fromJson({
                      'company': 'Sample Mill',
                      'knitting_enabled': true,
                      'capabilities': ['jobs', 'lifecycle'],
                    }),
                    action: knitActions.firstWhere((a) => a.id == 'reopen_job'),
                    job: {'name': 'JOB-1'},
                  ),
                ),
              ),
              child: const Text('Open entry'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Retain my entry',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave this entry?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Retain my entry'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Open entry'), findsOneWidget);
  });
  for (final (id, field, capability) in [
    ('bill_yarn', 'Original yarn receipt', 'billing'),
    ('return_consumable', 'Original consumable issue', 'factory'),
  ]) {
    testWidgets('$id reviews the source job and posts its selected version', (
      tester,
    ) async {
      final api = _SourceApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Sample Mill',
              'knitting_enabled': true,
              'capabilities': ['jobs', capability],
            }),
            action: knitActions.firstWhere((a) => a.id == id),
            initial: {
              if (id == 'bill_yarn')
                'quantity_kg': '2.000'
              else ...{
                'quantity': '2.000',
                'reason': 'Unused cones',
              },
            },
          ),
        ),
      );
      await tester.tap(
        find
            .ancestor(of: find.text(field), matching: find.byType(InkWell))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic source record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('JOB-FLOOR-07'), findsWidgets);
      expect(find.textContaining('Synthetic source record'), findsWidgets);
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(api.sourceVersion, '2026-11-13 10:00:00.000001');
      expect(api.posted?[id == 'bill_yarn' ? 'receipt' : 'event'], 'EVENT-01');
      expect(api.posted?.containsKey('job'), isFalse);
    });
  }
  testWidgets(
    'bulk production cannot be reviewed without line-specific consumption',
    (tester) async {
      final api = _SourceApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Sample Mill',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: knitActions.firstWhere((a) => a.id == 'produce_bulk'),
            job: {
              'name': 'JOB-T',
              'programme': [
                {'id': 'A', 'fabric': 'Rib', 'target_kg': '2.000'},
              ],
            },
            initial: {
              'entries': [
                {
                  'programme_line': 'A',
                  'machine': 'Machine 01',
                  'shift': 'Day',
                  'weights_kg': ['2.000'],
                  'loss_kg': '0',
                  'inputs': [],
                },
              ],
            },
          ),
        ),
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsNothing);
      expect(
        find.textContaining('Add at least one yarn input'),
        findsOneWidget,
      );
    },
  );
}

class _SourceApi extends ErpApi {
  _SourceApi() : super(Uri.parse('http://localhost:8081'));
  String? sourceVersion;
  Map<String, dynamic>? posted;
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
  }) async => {
    'rows': [
      if (entity == 'YarnReceipt' || entity == 'ConsumableIssue')
        {
          'name': 'EVENT-01',
          'title': 'Synthetic source record',
          'job': 'JOB-FLOOR-07',
          'job_modified': '2026-11-13 10:00:00.000001',
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
    posted = values;
    sourceVersion = modified;
    return {'event': 'EVENT-POSTED', 'data': {}};
  }
}
