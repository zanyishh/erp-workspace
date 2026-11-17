import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_register.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/mill_overview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/widgets.dart';

Map<String, dynamic> job(int i, [String company = 'Mill']) => {
  'name': '$company-JOB-$i',
  'customer': 'Customer $i',
  'status': i == 200 ? 'Running' : 'Completed',
  'target_kg': '1.000',
  'modified': 'version-$i',
  'programme': [],
  'balances': {'yarn_kg': '1.000', 'unbilled_kg': '0.000'},
};
Map<String, dynamic> pageInfo(int start, int total) => {
  'start': start,
  'limit': 100,
  'has_more': start + 100 < total,
  'total': total,
};
KnittingSnapshot sample(String company, {String? selected}) =>
    KnittingSnapshot(company, {
      'scope_job': selected,
      'jobs': selected == null
          ? List.generate(100, (i) => job(i, company))
          : [job(int.parse(selected.split('-').last), company)],
      'events': [],
      'rolls': [],
      'pagination': {
        'jobs': pageInfo(0, selected == null ? 201 : 1),
        'events': pageInfo(0, 0),
        'rolls': pageInfo(0, 0),
      },
    });
WorkspaceContext access(String company, {bool overview = false}) =>
    WorkspaceContext.fromJson({
      'company': company,
      'knitting_enabled': true,
      'setup_state': 'Active',
      'capabilities': [
        if (overview) 'overview',
        'jobs',
        'production',
        'quality',
        'materials',
        'billing',
        'financial_read',
      ],
    });

class PagesApi extends ErpApi {
  PagesApi() : super(Uri.parse('http://localhost:8081'));
  final calls = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? delayed;
  final exactRolls = <String>[];
  bool productionAvailable = true;
  bool unbilledAvailable = true;
  bool reconciliationAvailable = true;
  @override
  Future<Map<String, dynamic>> knittingRoll(
    String company,
    String job,
    String roll,
  ) async {
    exactRolls.add(roll);
    return {
      'company': company,
      'job': job,
      'name': roll,
      'state': 'Awaiting QC',
      'weight_kg': '1.000',
    };
  }

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async {
    final result = sample(company, selected: job);
    if (job == null || reconciliationAvailable) return result;
    return KnittingSnapshot(company, {
      ...result.data,
      'jobs': [
        {
          ...result.rows('jobs').single,
          'balances': null,
          'workflow': null,
          'reconciliation_available': false,
        },
      ],
    });
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
    calls.add({
      'company': company,
      'collection': collection,
      'job': job,
      'start': start,
      'query': query,
      'state': state,
      'date': productionDate,
    });
    if (delayed != null && company == 'Mill' && start == 100) {
      return delayed!.future;
    }
    final rows = collection == 'jobs'
        ? List.generate(201, (i) => jobRow(i, company))
        : List.generate(
            501,
            (i) => {
              'name': '$company-ROW-$i',
              'job': '$company-JOB-200',
              'state': i == 500 ? 'Awaiting QC' : 'Released',
              'kind': 'produce',
              'occurred_at': '2026-11-14 09:00:00',
              'result': {'quantity_kg': '1.000'},
            },
          );
    final matching = rows
        .where(
          (r) =>
              (query.isEmpty || r.values.join(' ').contains(query)) &&
              (state == null ||
                  (collection == 'jobs' ? r['status'] : r['state']) == state),
        )
        .toList();
    return {
      'version': 1,
      'company': company,
      'collection': collection,
      'scope_job': job,
      'query': query,
      'state': state,
      'rows': matching.skip(start).take(100).toList(),
      'page': pageInfo(start, matching.length),
    };
  }

  Map<String, dynamic> jobRow(int i, String company) => job(i, company);
  @override
  Future<Map<String, dynamic>> knittingOverview(String company) async => {
    'version': 1,
    'company': company,
    'jobs': {'total': 201, 'running': 1},
    'rolls': {'Awaiting QC': 501, 'On Hold': 0, 'Released': 0},
    'plans': {'Planned': 0},
    'balances': {
      'yarn_kg': '201.000',
      'unbilled_kg': unbilledAvailable ? '20.000' : null,
    },
    'production': productionAvailable
        ? [
            {'date': '2026-11-14', 'quantity_kg': '501.000', 'count': 501},
          ]
        : null,
  };
}

void main() {
  testWidgets(
    'restricted reconciliation suppresses suggestions but keeps permitted QC entry available',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PagesApi()..reconciliationAvailable = false;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: access('Mill'),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mill-JOB-200'));
      await tester.pumpAndSettle();
      expect(find.text('Reconciliation unavailable'), findsOneWidget);
      final metrics = tester.widgetList<MetricTile>(find.byType(MetricTile));
      expect(metrics, hasLength(4));
      expect(metrics.every((metric) => metric.value == '—'), isTrue);
      expect(
        metrics.every((metric) => metric.footer == 'Balance unavailable'),
        isTrue,
      );
      expect(find.byKey(const ValueKey('next-job-action')), findsNothing);
      expect(find.text('Receive yarn for the job'), findsNothing);
      await tester.tap(find.text('Quality').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect roll').first);
      await tester.pumpAndSettle();
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.action.id, 'quality');
      expect(form.job?['name'], 'Mill-JOB-200');
      expect(form.initial, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable company production never falls back to a partial page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PagesApi()
        ..productionAvailable = false
        ..unbilledAvailable = false;
      addTearDown(api.close);
      final snapshot = KnittingSnapshot('Mill', {
        ...sample('Mill').data,
        'events': [
          {
            'name': 'VISIBLE-PARTIAL-EVENT',
            'kind': 'produce',
            'cancelled': 0,
            'occurred_at': '2026-11-14 09:00:00',
            'result': {'quantity_kg': '123.000'},
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: Scaffold(
            body: MillOverview(
              api: api,
              snapshot: snapshot,
              workspace: access('Mill', overview: true),
              onDestination: (_, {filter}) {},
              onJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Production totals are unavailable with the current source access.',
        ),
        findsOneWidget,
      );
      expect(find.text('123 kg'), findsNothing);
      expect(find.byTooltip('View production entries'), findsNothing);
      await tester.tap(find.text('Awaiting invoice'));
      await tester.pumpAndSettle();
      expect(find.byType(KnittingSourcesDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all 501 records are reachable with bounded independent pages', (
    tester,
  ) async {
    final api = PagesApi();
    addTearDown(api.close);
    int start = 0;
    final seen = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => KnittingRegisterPage(
              api: api,
              snapshot: sample('Mill'),
              collection: 'events',
              productionDate: '2026-11-14',
              start: start,
              onPage: (value) => setState(() => start = value),
              builder: (rows, controls, loading) {
                seen.addAll(rows.map((r) => r['name'] as String));
                return Column(
                  children: [
                    controls,
                    Expanded(
                      child: ListView(
                        children: rows
                            .map((r) => Text('${r['name']}'))
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('events-next')));
      await tester.pumpAndSettle();
    }
    expect(api.calls.map((c) => c['start']), [0, 100, 200, 300, 400, 500]);
    expect(seen.length, 501);
    expect(find.text('Mill-ROW-500'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('events-next')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('advancing one register preserves the sibling register page', (
    tester,
  ) async {
    final api = PagesApi();
    addTearDown(api.close);
    final snapshot = sample('Mill');
    final starts = {'events': 0, 'rolls': 0};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                for (final collection in ['events', 'rolls'])
                  Expanded(
                    child: KnittingRegisterPage(
                      api: api,
                      snapshot: snapshot,
                      collection: collection,
                      query: 'ROW',
                      start: starts[collection]!,
                      onPage: (value) =>
                          setState(() => starts[collection] = value),
                      builder: (rows, controls, _) => Column(
                        children: [
                          controls,
                          Expanded(
                            child: ListView(
                              children: [
                                for (final row in rows)
                                  Text('$collection:${row['name']}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('events-next')));
    await tester.pumpAndSettle();
    expect(starts, {'events': 100, 'rolls': 0});
    expect(find.text('events:Mill-ROW-100'), findsOneWidget);
    expect(find.text('rolls:Mill-ROW-0'), findsOneWidget);
    expect(api.calls.where((r) => r['collection'] == 'rolls').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and queue state find an older match before pagination', (
    tester,
  ) async {
    final api = PagesApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnittingRegisterPage(
            api: api,
            snapshot: sample('Mill'),
            collection: 'rolls',
            query: 'ROW-500',
            state: 'Awaiting QC',
            onPage: (_) {},
            builder: (rows, controls, _) => Column(
              children: [controls, ...rows.map((r) => Text('${r['name']}'))],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mill-ROW-500'), findsOneWidget);
    expect(find.text('1–1 of 1 records'), findsOneWidget);
    expect(api.calls.single['state'], 'Awaiting QC');
    expect(api.calls.single['query'], 'ROW-500');
  });

  testWidgets(
    'Back restores the job register page and status search resets it',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PagesApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: access('Mill'),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jobs-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mill-JOB-100'));
      await tester.pumpAndSettle();
      expect(find.text('Job complete'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to jobs'));
      await tester.pumpAndSettle();
      expect(find.text('101–200 of 201 records'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Running'));
      await tester.pumpAndSettle();
      expect(find.text('Mill-JOB-200'), findsOneWidget);
      expect(find.text('1–1 of 1 records'), findsOneWidget);
      expect(api.calls.last['start'], 0);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search all jobs'),
        'Customer 200',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(api.calls.last['query'], 'Customer 200');
      expect(find.text('Mill-JOB-200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a previous company page cannot replace the new company', (
    tester,
  ) async {
    final api = PagesApi();
    addTearDown(api.close);
    api.delayed = Completer();
    Widget view(String company, int start) => MaterialApp(
      home: Scaffold(
        body: KnittingRegisterPage(
          api: api,
          snapshot: sample(company),
          collection: 'jobs',
          start: start,
          onPage: (_) {},
          builder: (rows, controls, _) => Column(
            children: [
              controls,
              Expanded(
                child: ListView(
                  children: rows.map((r) => Text('${r['name']}')).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(view('Mill', 100));
    await tester.pump();
    await tester.pumpWidget(view('Other', 0));
    await tester.pumpAndSettle();
    api.delayed!.complete({
      'version': 1,
      'company': 'Mill',
      'collection': 'jobs',
      'scope_job': null,
      'rows': [job(100)],
      'page': pageInfo(100, 201),
    });
    await tester.pumpAndSettle();
    expect(find.text('Other-JOB-0'), findsOneWidget);
    expect(find.text('Mill-JOB-100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an older roll opens from its exact source even outside the job first page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PagesApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingScreen(
            api: api,
            workspace: access('Mill', overview: true),
            onContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting inspection'));
      await tester.pumpAndSettle();
      expect(find.text('Mill-ROW-500'), findsOneWidget);
      await tester.tap(find.text('Mill-ROW-500'));
      await tester.pumpAndSettle();
      expect(api.exactRolls, ['Mill-ROW-500']);
      final form = tester.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.job?['name'], 'Mill-JOB-200');
      expect(form.job?['modified'], 'version-200');
      expect(form.initial, {'roll': 'Mill-ROW-500'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overview totals and production sources include records beyond the first page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PagesApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: Scaffold(
            body: MillOverview(
              api: api,
              snapshot: sample('Mill'),
              workspace: access('Mill', overview: true),
              onDestination: (_, {filter}) {},
              onJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('of 201 jobs'), findsOneWidget);
      expect(
        find.text('All 501 production entries in this period'),
        findsOneWidget,
      );
      expect(find.text('501 kg'), findsOneWidget);
      await tester.tap(find.byTooltip('View production entries'));
      await tester.pumpAndSettle();
      expect(find.text('1–100 of 501 records'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('events-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Mill-ROW-500'), findsOneWidget);
      expect(api.calls.last['date'], '2026-11-14');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.text('All 501 production entries in this period'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
