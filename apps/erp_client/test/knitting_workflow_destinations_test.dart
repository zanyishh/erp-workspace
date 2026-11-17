import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext access(List<String> capabilities, {bool estimates = true}) =>
    WorkspaceContext.fromJson({
      'company': 'Demo',
      'knitting_enabled': true,
      'setup_state': 'Active',
      'capabilities': ['jobs', ...capabilities],
      'readable_records': [if (estimates) 'Quotation'],
    });

void main() {
  test(
    'estimate and subcontract navigation follows read and operation access',
    () {
      expect(access(['billing']).destinations, contains('Estimation'));
      expect(access(['billing']).destinations, contains('Subcontracting'));
      expect(
        access([], estimates: false).destinations,
        isNot(contains('Estimation')),
      );
      expect(
        access([], estimates: false).destinations,
        isNot(contains('Subcontracting')),
      );
      expect(
        access(['materials'], estimates: false).destinations,
        contains('Subcontracting'),
      );
    },
  );
  testWidgets('operational choices are visible without opening More entries', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnittingWorkbench(
            snapshot: KnittingSnapshot.fromJson({
              'version': 1,
              'company': 'Demo',
            }),
            page: 'Yarn',
            selected: null,
            query: '',
            onQuery: (_) {},
            onJob: (_) {},
            onFind: () {},
            onAction: (action, {initial = const {}}) async =>
                opened.add(action.id),
            onSource: (_, _) async {},
            workspace: access(['materials']),
          ),
        ),
      ),
    );
    expect(find.text('Issue to subcontractor'), findsOneWidget);
    await tester.tap(find.text('Issue to subcontractor'));
    expect(opened, ['subcontract_issue']);
  });
  testWidgets(
    'dedicated destinations open operational registers and create entry',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WorkflowApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access([
              'billing',
              'materials',
              'factory',
              'lifecycle',
              'new_job',
              'financial_read',
            ]),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estimation').first);
      await tester.pumpAndSettle();
      expect(api.collections, contains('estimates'));
      expect(find.text('EST-1'), findsOneWidget);
      expect(find.text('Customer One'), findsOneWidget);
      expect(find.textContaining('1200.00'), findsOneWidget);
      expect(find.text('2026-11-15'), findsOneWidget);
      await tester.tap(find.text('New estimate'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<KnittingCommandForm>(find.byType(KnittingCommandForm))
            .action
            .id,
        'create_estimate',
      );
      expect(api.collections.where((c) => c == 'subcontracts'), isEmpty);
    },
  );

  testWidgets(
    'original programme revision explains its limit and keeps rate available',
    (tester) async {
      final job = <String, dynamic>{
        'name': 'JOB-1',
        'status': 'Running',
        'target_kg': '12.000',
        'programme': [
          {
            'id': 'P1',
            'source_line_id': 'original-1',
            'fabric': 'Single jersey',
            'target_kg': '12.000',
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingWorkbench(
              snapshot: KnittingSnapshot.fromJson({
                'version': 1,
                'company': 'Demo',
                'jobs': [job],
              }),
              page: 'Jobs',
              selected: job,
              query: '',
              onQuery: (_) {},
              onJob: (_) {},
              onFind: () {},
              onAction: (action, {initial = const {}}) async {},
              onSource: (_, _) async {},
              workspace: access(['lifecycle', 'financial_read']),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Original programme changes are not available. You can revise the rate.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Original programme changes are not available. You can revise the rate.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Revise programme'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Revise rate'), findsOneWidget);
    },
  );

  testWidgets('estimate controls and list fit a short phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = WorkflowApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: KnittingScreen(
          api: api,
          workspace: access(['billing', 'financial_read']),
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estimation').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('EST-1'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final estimate = find.widgetWithText(ListTile, 'EST-1');
    expect(estimate.hitTestable(), findsOneWidget);
    await tester.tap(estimate);
    await tester.pumpAndSettle();
    expect(find.textContaining('Single jersey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'estimate date range and page survive job Back and action refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WorkflowApi()
        ..multiplePages = true
        ..converted = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access(['billing', 'new_job', 'financial_read']),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estimation').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'From date · YYYY-MM-DD'),
        '2026-11-01',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'To date · YYYY-MM-DD'),
        '2026-11-15',
      );
      await tester.tap(find.text('Apply dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('estimates-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EST-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open converted job'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to estimation'));
      await tester.pumpAndSettle();
      expect(api.registerRequests.last, {
        'start': 100,
        'from': '2026-11-01',
        'to': '2026-11-15',
      });
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'From date · YYYY-MM-DD'),
            )
            .controller!
            .text,
        '2026-11-01',
      );
      await tester.tap(find.text('New estimate'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.registerRequests.last, {
        'start': 0,
        'from': '2026-11-01',
        'to': '2026-11-15',
      });
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'To date · YYYY-MM-DD'),
            )
            .controller!
            .text,
        '2026-11-15',
      );
    },
  );

  testWidgets(
    'estimate reader sees neither totals nor commercial write actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WorkflowApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access([]),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estimation').first);
      await tester.pumpAndSettle();
      expect(find.text('New estimate'), findsNothing);
      expect(find.textContaining('1200.00'), findsNothing);
      await tester.tap(find.text('EST-1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Single jersey'), findsOneWidget);
      expect(find.textContaining('1200.00'), findsNothing);
      expect(find.text('Accept estimate'), findsNothing);
      expect(find.text('Job from estimate'), findsNothing);
    },
  );

  testWidgets(
    'estimate dates filter the server register and reject reversed ranges',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WorkflowApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access(['billing']),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estimation').first);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'From date · YYYY-MM-DD'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'From date · YYYY-MM-DD'),
        '2026-11-01',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'To date · YYYY-MM-DD'),
        '2026-11-15',
      );
      await tester.tap(find.text('Apply dates'));
      await tester.pumpAndSettle();
      expect(api.dateRequests.last, ('2026-11-01', '2026-11-15'));
      final requests = api.dateRequests.length;
      await tester.enterText(
        find.widgetWithText(TextField, 'To date · YYYY-MM-DD'),
        '2026-10-30',
      );
      await tester.tap(find.text('Apply dates'));
      await tester.pumpAndSettle();
      expect(api.dateRequests.length, requests);
      expect(
        find.text('From date must be on or before To date.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear dates'));
      await tester.pumpAndSettle();
      expect(api.dateRequests.last, (null, null));
    },
  );

  testWidgets('subcontract register opens a job-versioned scoped issue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = WorkflowApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: KnittingScreen(
          api: api,
          workspace: access(['materials']),
          onContextChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subcontracting').first);
    await tester.pumpAndSettle();
    expect(api.collections, contains('subcontracts'));
    await tester.tap(find.text('SUB-1'));
    await tester.pumpAndSettle();
    expect(find.text('Complete subcontract'), findsNothing);
    await tester.tap(find.text('Issue to subcontractor').last);
    await tester.pumpAndSettle();
    final form = tester.widget<KnittingCommandForm>(
      find.byType(KnittingCommandForm),
    );
    expect(form.action.id, 'subcontract_issue');
    expect(form.job?['name'], 'JOB-1');
    expect(form.job?['modified'], 'job-current');
    expect(form.initial['subcontract'], 'SUB-1');
    expect(form.initialReferences['subcontract']?['job'], 'JOB-1');
  });

  testWidgets(
    'estimate detail selects current version and hides invalid state actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WorkflowApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingScreen(
            api: api,
            workspace: access(['billing', 'new_job', 'financial_read']),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Estimation').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('EST-1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Single jersey'), findsOneWidget);
      expect(find.text('Accept estimate'), findsOneWidget);
      expect(find.text('Job from estimate'), findsNothing);
      await tester.tap(find.text('Accept estimate'));
      await tester.pumpAndSettle();
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.initial['quotation'], 'EST-1');
      expect(form.initialReferences['quotation']?['modified'], 'v1');
      await tester.pageBack();
      await tester.pumpAndSettle();
      api.docstatus = 1;
      await tester.tap(find.text('EST-1'));
      await tester.pumpAndSettle();
      expect(find.text('Accept estimate'), findsNothing);
      expect(find.text('Job from estimate'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      api.converted = true;
      await tester.tap(find.text('EST-1'));
      await tester.pumpAndSettle();
      expect(find.text('Accept estimate'), findsNothing);
      expect(find.text('Job from estimate'), findsNothing);
      expect(find.text('Converted'), findsOneWidget);
      api.publishContext(access(['billing', 'new_job', 'financial_read']));
      api.publishContext(
        WorkspaceContext.fromJson({'company': 'Demo', 'capabilities': []}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Single jersey'), findsNothing);
      expect(find.textContaining('Access changed.'), findsWidgets);
    },
  );
}

class WorkflowApi extends ErpApi {
  WorkflowApi() : super(Uri.parse('http://127.0.0.1:8082'));
  final collections = <String>[];
  final dateRequests = <(String?, String?)>[];
  int docstatus = 0;
  bool converted = false;
  bool multiplePages = false;
  final registerRequests = <Map<String, dynamic>>[];
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      access(['billing', 'new_job', 'financial_read']);
  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': {
      'name': name,
      'company': company,
      'modified': 'v1',
      'knitting_material_mode': 'Customer',
      'knitting_programme': [
        {'fabric': 'Single jersey', 'target_kg': '12.000'},
      ],
    },
  });
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    String? job,
    int start = 0,
  }) async => {
    'rows': [
      {
        'name': 'SUB-1',
        'job': 'JOB-1',
        'supplier': 'Supplier One',
        'status': 'Open',
      },
    ],
  };
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot.fromJson({
    'version': 1,
    'company': company,
    'pagination': {},
    'jobs': [
      if (job != null)
        {
          'name': job,
          'modified': 'job-current',
          'status': 'Running',
          'programme': [],
        },
    ],
  });
  @override
  Future<Map<String, dynamic>> knittingRegister(
    String company,
    String collection, {
    String? job,
    int start = 0,
    String query = '',
    String? state,
    String? productionDate,
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
  }) async {
    collections.add(collection);
    dateRequests.add((fromDate, toDate));
    if (collection == 'estimates') {
      registerRequests.add({'start': start, 'from': fromDate, 'to': toDate});
    }
    return {
      'version': 1,
      'company': company,
      'collection': collection,
      'scope_job': job,
      'from_date': fromDate,
      'to_date': toDate,
      'rows': collection == 'estimates'
          ? [
              {
                'name': 'EST-1',
                'modified': 'v1',
                'transaction_date': '2026-11-15',
                'party_name': 'CUST-1',
                'customer_name': 'Customer One',
                'status': docstatus == 0 ? 'Draft' : 'Open',
                'docstatus': docstatus,
                'grand_total': '1200.00',
                'currency': 'INR',
                'converted': converted,
                'job': converted ? 'JOB-1' : null,
              },
            ]
          : collection == 'subcontracts'
          ? [
              {
                'name': 'SUB-1',
                'job': 'JOB-1',
                'supplier': 'Supplier One',
                'status': 'Open',
                'target_kg': '12.000',
              },
            ]
          : [],
      'page': {
        'start': start,
        'limit': 100,
        'has_more': collection == 'estimates' && multiplePages && start == 0,
        'total': collection == 'estimates' && multiplePages
            ? 101
            : ['estimates', 'subcontracts'].contains(collection)
            ? 1
            : 0,
      },
    };
  }
}
