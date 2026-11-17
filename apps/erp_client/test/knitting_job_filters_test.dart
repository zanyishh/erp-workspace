import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/knitting_register.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext jobAccess(String company, {String fingerprint = 'before'}) =>
    WorkspaceContext.fromJson({
      'company': company,
      'knitting_enabled': true,
      'setup_state': 'Active',
      'capabilities': ['jobs', 'new_job', 'lifecycle', 'financial_read'],
      'access_fingerprint': fingerprint,
    });

class JobsFiltersApi extends ErpApi {
  JobsFiltersApi() : super(Uri.parse('http://127.0.0.1:8081'));
  final requests = <Map<String, dynamic>>[];
  final lookups = <(String, String)>[];
  Completer<Map<String, dynamic>>? delayedPage;
  Completer<Map<String, dynamic>>? delayedCustomer;
  bool wrongEcho = false;
  String currentCompany = 'Mill';
  Map<String, dynamic> jobRow(String name) => {
    'name': name,
    'customer': 'CUST-001',
    'customer_name': 'Exact Mills',
    'status': 'Running',
    'target_kg': '12.000',
    'modified': 'current-version',
    'job_date': '2026-11-01',
    'programme': [],
    'balances': {'yarn_kg': '0.000', 'unbilled_kg': '0.000'},
  };

  Map<String, dynamic> response(
    String company,
    int start,
    String? customer,
    String? from,
    String? to,
  ) => {
    'version': 1,
    'company': company,
    'collection': 'jobs',
    'scope_job': null,
    'customer': wrongEcho ? 'OTHER' : customer,
    'from_date': from,
    'to_date': to,
    'rows': [jobRow('$company-JOB-$start')],
    'page': {
      'start': start,
      'limit': 100,
      'has_more': start == 0,
      'total': 101,
    },
  };

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot.fromJson({
    'version': 1,
    'company': company,
    'scope_job': job,
    'pagination': <String, dynamic>{},
    'jobs': [if (job != null) jobRow(job)],
  });

  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      jobAccess(company ?? currentCompany);

  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    String? job,
    int start = 0,
  }) async {
    lookups.add((company, entity));
    if (delayedCustomer != null) return delayedCustomer!.future;
    return {
      'rows': [
        {
          'name': 'CUST-001',
          'customer_name': 'Exact Mills',
          'title': 'Exact Mills',
        },
        {
          'name': 'CUST-002',
          'customer_name': 'Exact Mills Annex',
          'title': 'Exact Mills Annex',
        },
      ],
      'has_more': false,
      'can_create': false,
    };
  }

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
    requests.add({
      'company': company,
      'collection': collection,
      'start': start,
      'query': query,
      'state': state,
      'customer': customer,
      'from': fromDate,
      'to': toDate,
    });
    if (delayedPage != null && customer == 'CUST-001') {
      return delayedPage!.future;
    }
    return response(company, start, customer, fromDate, toDate);
  }
}

Future<void> showJobs(
  WidgetTester t,
  JobsFiltersApi api, {
  String company = 'Mill',
  String fingerprint = 'before',
}) async {
  api.currentCompany = company;
  await t.pumpWidget(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: KnittingScreen(
        api: api,
        workspace: jobAccess(company, fingerprint: fingerprint),
        onContextChanged: (_) {},
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> chooseCustomer(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('jobs-customer')));
  await t.pumpAndSettle();
  expect(find.text('SELECT CUSTOMER'), findsOneWidget);
  expect(find.text('CUST-001'), findsNothing);
  await t.tap(find.text('Exact Mills').last);
  await t.pumpAndSettle();
}

void desktop(WidgetTester t) {
  t.view.physicalSize = const Size(1440, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> revealJobControl(
  WidgetTester t,
  Finder target, {
  bool upward = false,
}) async {
  for (var i = 0; i < 24 && target.hitTestable().evaluate().isEmpty; i++) {
    await t.drag(
      find.byType(CustomScrollView).first,
      Offset(0, upward ? 180 : -180),
    );
    await t.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'job customer and date drafts apply together and clear the paged view',
    (t) async {
      desktop(t);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      await showJobs(t, api);
      expect(find.byKey(const ValueKey('jobs-customer')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('jobs-next')));
      await t.pumpAndSettle();
      expect(api.requests.last['start'], 100);
      final before = api.requests.length;
      await chooseCustomer(t);
      await t.enterText(
        find.byKey(const ValueKey('jobs-from-date')),
        '2026-11-01',
      );
      await t.enterText(
        find.byKey(const ValueKey('jobs-to-date')),
        '2026-11-15',
      );
      expect(api.requests.length, before);
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.requests.last, {
        'company': 'Mill',
        'collection': 'jobs',
        'start': 0,
        'query': '',
        'state': null,
        'customer': 'CUST-001',
        'from': '2026-11-01',
        'to': '2026-11-15',
      });
      expect(api.lookups, [('Mill', 'JobCustomer')]);
      expect(find.textContaining('CUST-001'), findsNothing);
      await t.tap(find.byKey(const ValueKey('jobs-next')));
      await t.pumpAndSettle();
      expect(api.requests.last['customer'], 'CUST-001');
      expect(api.requests.last['start'], 100);
      await t.tap(find.text('Clear filters'));
      await t.pumpAndSettle();
      expect(api.requests.last['customer'], isNull);
      expect(api.requests.last['from'], isNull);
      expect(api.requests.last['to'], isNull);
      expect(api.requests.last['start'], 0);
    },
  );

  testWidgets(
    'applied job filters and page survive detail Back and action refresh',
    (t) async {
      desktop(t);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      await showJobs(t, api);
      await chooseCustomer(t);
      await t.enterText(
        find.byKey(const ValueKey('jobs-from-date')),
        '2026-11-01',
      );
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('jobs-next')));
      await t.pumpAndSettle();
      await t.tap(find.text('Mill-JOB-100'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Back to jobs'));
      await t.pumpAndSettle();
      expect(api.requests.last['start'], 100);
      expect(api.requests.last['customer'], 'CUST-001');
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('jobs-from-date')))
            .controller!
            .text,
        '2026-11-01',
      );
      await t.tap(find.text('New job').first);
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(api.requests.last['start'], 0);
      expect(api.requests.last['customer'], 'CUST-001');
      expect(api.requests.last['from'], '2026-11-01');
    },
  );

  testWidgets('date-only drafts can be cleared before applying filters', (
    t,
  ) async {
    desktop(t);
    final api = JobsFiltersApi();
    addTearDown(api.close);
    await showJobs(t, api);
    await t.enterText(
      find.byKey(const ValueKey('jobs-from-date')),
      '2026-11-01',
    );
    await t.pump();
    expect(find.text('Clear filters'), findsOneWidget);
    await t.tap(find.text('Clear filters'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('jobs-from-date')))
          .controller!
          .text,
      isEmpty,
    );
    expect(api.requests.last['from'], isNull);
  });

  testWidgets(
    'invalid or reversed job dates leave applied criteria unchanged',
    (t) async {
      desktop(t);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      await showJobs(t, api);
      final before = api.requests.length;
      await t.enterText(
        find.byKey(const ValueKey('jobs-from-date')),
        '2026-02-30',
      );
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.requests.length, before);
      expect(find.text('Enter valid dates as YYYY-MM-DD.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('jobs-from-date')),
        '2026-11-15',
      );
      await t.enterText(
        find.byKey(const ValueKey('jobs-to-date')),
        '2026-11-01',
      );
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.requests.length, before);
      expect(
        find.text('From date must be on or before To date.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('old filtered page cannot replace a cleared job view', (t) async {
    desktop(t);
    final api = JobsFiltersApi();
    addTearDown(api.close);
    await showJobs(t, api);
    await chooseCustomer(t);
    api.delayedPage = Completer();
    await t.tap(find.text('Apply filters'));
    await t.pump();
    await t.tap(find.text('Clear filters'));
    await t.pumpAndSettle();
    api.delayedPage!.complete({
      ...api.response('Mill', 0, 'CUST-001', null, null),
      'rows': [api.jobRow('STALE-JOB')],
    });
    await t.pumpAndSettle();
    expect(find.text('STALE-JOB'), findsNothing);
    expect(find.text('Mill-JOB-0'), findsOneWidget);
  });

  testWidgets('mismatched applied job filter echo fails closed', (t) async {
    desktop(t);
    final api = JobsFiltersApi();
    addTearDown(api.close);
    await showJobs(t, api);
    await chooseCustomer(t);
    api.wrongEcho = true;
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    expect(find.text('Mill-JOB-0'), findsNothing);
    expect(find.textContaining('unexpected page'), findsOneWidget);
  });

  testWidgets('company and access changes clear applied job criteria', (
    t,
  ) async {
    desktop(t);
    final api = JobsFiltersApi();
    addTearDown(api.close);
    await showJobs(t, api);
    await chooseCustomer(t);
    await t.enterText(
      find.byKey(const ValueKey('jobs-from-date')),
      '2026-11-01',
    );
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    await showJobs(t, api, company: 'Other');
    expect(api.requests.last['company'], 'Other');
    expect(api.requests.last['customer'], isNull);
    expect(api.requests.last['from'], isNull);
    await chooseCustomer(t);
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    await showJobs(t, api, company: 'Other', fingerprint: 'changed');
    expect(api.requests.last['customer'], isNull);
    expect(api.requests.last['start'], 0);
  });

  testWidgets(
    'a filtered Jobs request never reuses the unfiltered snapshot page',
    (t) async {
      final api = JobsFiltersApi();
      addTearDown(api.close);
      final snapshot = KnittingSnapshot.fromJson({
        'version': 1,
        'company': 'Mill',
        'scope_job': null,
        'jobs': [api.jobRow('UNFILTERED-CACHE')],
        'pagination': {
          'jobs': {'start': 0, 'limit': 100, 'total': 1, 'has_more': false},
        },
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingRegisterPage(
              api: api,
              snapshot: snapshot,
              collection: 'jobs',
              customer: 'CUST-001',
              fromDate: '2026-11-01',
              onPage: (_) {},
              builder: (rows, controls, loading) => Column(
                children: [
                  controls,
                  ...rows.map((r) => Text(r['name'] as String)),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('UNFILTERED-CACHE'), findsNothing);
      expect(find.text('Mill-JOB-0'), findsOneWidget);
      expect(api.requests.single['customer'], 'CUST-001');
      expect(api.requests.single['from'], '2026-11-01');
    },
  );

  testWidgets(
    'an older company filtered request cannot restore its customer or rows',
    (t) async {
      desktop(t);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      await showJobs(t, api);
      await chooseCustomer(t);
      api.delayedPage = Completer();
      await t.tap(find.text('Apply filters'));
      await t.pump();
      await showJobs(t, api, company: 'Other');
      api.delayedPage!.complete({
        ...api.response('Mill', 0, 'CUST-001', null, null),
        'rows': [api.jobRow('STALE-MILL-JOB')],
      });
      await t.pumpAndSettle();
      expect(find.text('STALE-MILL-JOB'), findsNothing);
      expect(find.text('Other-JOB-0'), findsOneWidget);
      expect(api.requests.last['customer'], isNull);
    },
  );

  testWidgets(
    'a customer chosen after access changes cannot apply the old picker result',
    (t) async {
      desktop(t);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      api.publishContext(jobAccess('Mill'));
      await showJobs(t, api);
      api.delayedCustomer = Completer();
      await t.tap(find.byKey(const ValueKey('jobs-customer')));
      await t.pump();
      api.publishContext(jobAccess('Mill', fingerprint: 'after'));
      await t.pump();
      api.delayedCustomer!.complete({
        'rows': [
          {'name': 'CUST-001', 'title': 'Late customer'},
        ],
        'has_more': false,
        'can_create': false,
      });
      await t.pumpAndSettle();
      if (find.text('Late customer').evaluate().isNotEmpty) {
        await t.tap(find.text('Late customer'));
        await t.pumpAndSettle();
      }
      expect(api.requests.last['customer'], isNull);
      expect(find.text('Applied: Late customer'), findsNothing);
    },
  );

  testWidgets(
    'job filters fit short phone large text and preserve search/status criteria',
    (t) async {
      t.view.physicalSize = const Size(390, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = JobsFiltersApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: KnittingScreen(
            api: api,
            workspace: jobAccess('Mill'),
            onContextChanged: (_) {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await revealJobControl(t, find.text('Apply filters'));
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await revealJobControl(
        t,
        find.widgetWithText(ChoiceChip, 'Running'),
        upward: true,
      );
      await t.tap(find.widgetWithText(ChoiceChip, 'Running'));
      await t.pumpAndSettle();
      expect(api.requests.last['state'], 'Running');
    },
  );
}
