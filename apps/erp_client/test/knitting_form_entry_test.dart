import 'dart:async';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final permitted in [true, false]) {
    testWidgets('empty customer picker respects create permission $permitted', (
      tester,
    ) async {
      final api = _SourceApi()..canCreateCustomer = permitted;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    pickKnitRecord(context, api, 'Sample Mill', 'Customer'),
                child: const Text('Choose a customer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose a customer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Create customer'),
        permitted ? findsOneWidget : findsNothing,
      );
    });
  }
  testWidgets('stale invoice preview offers source reload before any write', (
    tester,
  ) async {
    final api = _SourceApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: KnittingCommandForm(
          api: api,
          workspace: WorkspaceContext.fromJson({
            'company': 'Sample Mill',
            'knitting_enabled': true,
            'capabilities': ['jobs', 'billing'],
          }),
          action: knitActions.firstWhere((a) => a.id == 'invoice'),
          job: {'name': 'JOB-B', 'modified': 'v1'},
          initial: {
            'deliveries': ['DC-1'],
          },
        ),
      ),
    );
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    expect(find.text('Reload current sources'), findsOneWidget);
    await tester.tap(find.text('Reload current sources'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DC-1'), findsNothing);
    expect(find.text('Review entry'), findsOneWidget);
    expect(api.writes, 0);
  });
  testWidgets(
    'typing a roll code hides old choices until its search resolves',
    (tester) async {
      final api = _SourceApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    pickKnitRecord(context, api, 'Sample Mill', 'Roll'),
                child: const Text('Select a roll'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select a roll'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier roll'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Z-400');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Earlier roll'), findsNothing);
      api.rollSearch.complete({'rows': [], 'has_more': false});
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching records'), findsOneWidget);
      expect(find.text('1–0'), findsNothing);
    },
  );
  testWidgets(
    'stale revision reloads the current programme and retains the reason before review',
    (tester) async {
      final api = _SourceApi()..conflict = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Sample Mill',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'lifecycle'],
            }),
            action: knitActions.firstWhere((a) => a.id == 'revise_job'),
            job: {
              'name': 'JOB-B',
              'modified': 'v1',
              'programme': [
                {'id': 'P1', 'fabric': 'Original fabric', 'target_kg': '5'},
              ],
            },
            initial: {'reason': 'Repair the specification'},
          ),
        ),
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(find.text('Reload current sources'), findsOneWidget);
      expect(find.text('Check save status'), findsNothing);
      await tester.tap(find.text('Reload current sources'));
      await tester.pumpAndSettle();
      expect(find.text('Current fabric'), findsWidgets);
      expect(find.text('Repair the specification'), findsOneWidget);
      expect(api.writes, 1);
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(api.sourceVersion, 'v2');
      expect(api.posted?['programme']?.single['fabric'], 'Current fabric');
    },
  );
  Future<void> openEntry(
    WidgetTester tester,
    _SourceApi api,
    String id, {
    Map<String, dynamic> initial = const {},
  }) async {
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: KnittingCommandForm(
          api: api,
          workspace: WorkspaceContext.fromJson({
            'company': 'Sample Mill',
            'knitting_enabled': true,
            'capabilities': [
              'jobs',
              'financial_read',
              'lifecycle',
              'delivery',
              'production',
            ],
          }),
          action: knitActions.firstWhere((a) => a.id == id),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseJob(WidgetTester tester, String customer) async {
    final field = find
        .ancestor(of: find.text('Job'), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(customer).first);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'programme revision loads the selected job and preserves its agreed rates',
    (tester) async {
      final api = _SourceApi();
      await openEntry(
        tester,
        api,
        'revise_job',
        initial: {'reason': 'Recheck fabric'},
      );
      await chooseJob(tester, 'Second Mill');
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsOneWidget);
      expect(find.text('Interlock'), findsWidgets);
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(api.posted?['programme']?.single['id'], 'JOB-B-LINE');
      expect(api.posted!.containsKey('rate'), isFalse);
      expect(api.sourceVersion, 'JOB-B-v2');
    },
  );

  testWidgets(
    'changing dispatch job removes rolls selected on the previous job',
    (tester) async {
      final api = _SourceApi();
      await openEntry(
        tester,
        api,
        'deliver',
        initial: {
          'job': 'JOB-A',
          'rolls': ['FIRST-ROLL'],
        },
      );
      await chooseJob(tester, 'Second Mill');
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsNothing);
      expect(find.text('Choose released rolls.'), findsOneWidget);
      expect(find.textContaining('FIRST-ROLL'), findsNothing);
    },
  );

  testWidgets(
    'production review reconciles measured roll kg against actual yarn and loss',
    (tester) async {
      final api = _SourceApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: WorkspaceContext.fromJson({
              'company': 'Sample Mill',
              'knitting_enabled': true,
              'capabilities': ['jobs', 'production'],
            }),
            action: knitActions.firstWhere((a) => a.id == 'produce'),
            job: {
              'name': 'JOB-B',
              'programme': [
                {'id': 'P1', 'fabric': 'Interlock', 'target_kg': '20.000'},
              ],
            },
            initial: {
              'programme_line': 'P1',
              'shift': 'Day',
              'weights_kg': ['20'],
              'inputs': [
                {'lot': 'LOT-B', 'quantity_kg': '19.999'},
              ],
            },
          ),
        ),
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsNothing);
      expect(find.textContaining('19.999 kg of yarn'), findsOneWidget);
      final quantity = find.widgetWithText(TextFormField, 'Quantity · kg');
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '20');
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsOneWidget);
    },
  );
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
  bool canCreateCustomer = false;
  bool conflict = false;
  int writes = 0;
  final rollSearch = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> knittingInvoicePreview(
    String company,
    Map<String, dynamic> values,
    String? modified,
  ) async {
    throw const ErpException('Job changed', staleDocument: true);
  }

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {
    'jobs': [
      {
        'name': job,
        'modified': 'v2',
        'programme': [
          {'id': 'P1', 'fabric': 'Current fabric', 'target_kg': '5'},
        ],
      },
    ],
  });
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => entity == 'Roll' && query.isNotEmpty
      ? rollSearch.future
      : {
          if (entity == 'Customer') 'can_create': canCreateCustomer,
          'rows': [
            if (entity == 'Roll') {'name': 'X-300', 'title': 'Earlier roll'},
            if (entity == 'Job')
              {
                'name': 'JOB-B',
                'customer': 'Second Mill',
                'modified': 'JOB-B-v2',
                'programme': [
                  {
                    'id': 'JOB-B-LINE',
                    'fabric': 'Interlock',
                    'target_kg': '20.000',
                  },
                ],
              },
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
    writes++;
    if (conflict && writes == 1) {
      throw const ErpException('The source changed.', staleDocument: true);
    }
    posted = values;
    sourceVersion = modified;
    return {'event': 'EVENT-POSTED', 'data': {}};
  }
}
