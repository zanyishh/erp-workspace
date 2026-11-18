import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/imported_history.dart';
import 'package:erp_client/knitting_reports.dart';
import 'package:erp_client/original_production_report.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class OriginalReportApi extends ErpApi {
  OriginalReportApi() : super(Uri.parse('http://127.0.0.1:8082')) {
    access('Archive One', true, 'before');
  }
  final requests = <(String, String, int, Map<String, dynamic>)>[];
  final historyRequests = <(String, String, Map<String, dynamic>)>[];
  Completer<Map<String, dynamic>>? delayed;
  bool wrongScope = false;

  void access(String company, bool allowed, String fingerprint) =>
      publishContext(
        WorkspaceContext.fromJson({
          'company': company,
          'can_read_imported_history': allowed,
          'knitting_enabled': true,
          'capabilities': ['reports'],
          'access_fingerprint': fingerprint,
        }),
      );

  Map<String, dynamic> page(String company, String group, int start) => {
    'version': 1,
    'company': wrongScope ? 'Other Company' : company,
    'family': 'production',
    'group_by': group,
    'filters': requests.last.$4,
    'start': start,
    'page_length': 100,
    'row_count': 101,
    'has_more': start == 0,
    'available_filters': [
      'source_book',
      'party',
      'job',
      'shift',
      'machine',
      'operator',
      'description',
      'dia',
    ],
    'totals': {
      'source_record_count': 103,
      'quantity_kg': '-0.000',
      'recorded_count': '1.2500',
      'missing_quantity_rows': 2,
      'missing_count_rows': 3,
    },
    'rows': [
      {
        'value': group == 'original_date' ? '2024-04-05' : 'Saved label',
        'label': group == 'original_date' ? '2024-04-05' : 'Saved label',
        'drillable': true,
        'filters': {
          ...requests.last.$4,
          if (group == 'original_date') ...{
            'date_basis': 'original',
            'from_date': '2024-04-05',
            'to_date': '2024-04-05',
          } else
            group: 'Saved label',
        },
        'source_record_count': 2,
        'quantity_kg': '0.123456789',
        'recorded_count': null,
        'missing_quantity_rows': 0,
        'missing_count_rows': 2,
      },
      {
        'value': null,
        'label': 'Unrecorded',
        'drillable': group == 'original_date',
        'filters': group == 'original_date'
            ? {...requests.last.$4, 'date_basis': 'no_original'}
            : null,
        'source_record_count': 1,
        'quantity_kg': null,
        'recorded_count': null,
        'missing_quantity_rows': 1,
        'missing_count_rows': 1,
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> originalProductionSummary(
    String company, {
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  }) async {
    requests.add((company, groupBy, start, Map.from(filters)));
    if (delayed != null && requests.length == 1) return delayed!.future;
    return page(company, groupBy, start);
  }

  @override
  Future<Map<String, dynamic>> importedHistorySummary(String company) async => {
    'version': 1,
    'company': company,
    'families': [
      {'key': 'production', 'label': 'Production', 'count': 103},
    ],
    'shared_cash_available': false,
  };

  @override
  Future<Map<String, dynamic>> importedHistoryRecords(
    String company,
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async {
    historyRequests.add((company, family, Map.from(filters)));
    return {
      'version': 1,
      'company': company,
      'family': family,
      'start': start,
      'page_length': pageLength,
      'has_more': false,
      'row_count': 0,
      'available_filters': ['party', 'machine'],
      'rows': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async => {
    'columns': <Map<String, dynamic>>[],
    'rows': <Map<String, dynamic>>[],
    'summary': <String, dynamic>{},
    'row_count': 0,
    'start': 0,
    'has_more': false,
  };
}

Future<void> showReport(
  WidgetTester t,
  OriginalReportApi api, {
  String company = 'Archive One',
  Map<String, dynamic> filters = const {},
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: OriginalProductionReport(
        api: api,
        company: company,
        initialFilters: filters,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(
  WidgetTester t,
  Finder target, {
  bool upward = false,
}) async {
  for (var i = 0; i < 24 && target.hitTestable().evaluate().isEmpty; i++) {
    await t.drag(find.byType(ListView).first, Offset(0, upward ? 200 : -200));
    await t.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('original totals preserve exact signed zero and missing counts', (
    t,
  ) async {
    final api = OriginalReportApi();
    addTearDown(api.close);
    await showReport(t, api);
    expect(api.requests.single.$2, 'original_date');
    expect(find.text('-0.000'), findsOneWidget);
    expect(find.text('1.2500'), findsOneWidget);
    expect(find.text('0.123456789'), findsOneWidget);
    expect(find.textContaining('2 records without kg'), findsOneWidget);
    expect(
      find.textContaining('3 records without rolls / PCS'),
      findsOneWidget,
    );
    expect(find.textContaining('Identical saved labels'), findsOneWidget);
    expect(find.text('Original production · Read-only'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets(
    'grouping resets pagination and drilldown preserves exact filters',
    (t) async {
      final api = OriginalReportApi();
      addTearDown(api.close);
      await showReport(t, api, filters: {'party': 'Customer 00'});
      await reveal(t, find.text('Next groups'));
      await t.tap(find.text('Next groups'));
      await t.pumpAndSettle();
      expect(api.requests.last.$3, 100);
      await reveal(
        t,
        find.byKey(const ValueKey('original-production-group')),
        upward: true,
      );
      await t.tap(find.byKey(const ValueKey('original-production-group')));
      await t.pumpAndSettle();
      await t.tap(find.text('Machine').last);
      await t.pumpAndSettle();
      expect(api.requests.last.$2, 'machine');
      expect(api.requests.last.$3, 0);
      expect(api.requests.last.$4, {'party': 'Customer 00'});
      await reveal(t, find.text('Saved label'));
      await t.tap(find.text('Saved label'));
      await t.pumpAndSettle();
      expect(api.historyRequests.last.$1, 'Archive One');
      expect(api.historyRequests.last.$2, 'production');
      expect(api.historyRequests.last.$3, {
        'party': 'Customer 00',
        'machine': 'Saved label',
      });
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Saved label'), findsOneWidget);
      expect(api.requests.length, 3);
    },
  );

  testWidgets('missing labels without an exact selector cannot drill down', (
    t,
  ) async {
    final api = OriginalReportApi();
    addTearDown(api.close);
    await showReport(t, api);
    await t.tap(find.byKey(const ValueKey('original-production-group')));
    await t.pumpAndSettle();
    await t.tap(find.text('Machine').last);
    await t.pumpAndSettle();
    final unrecorded = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'Unrecorded',
    );
    await reveal(t, unrecorded);
    await t.tap(unrecorded);
    await t.pumpAndSettle();
    expect(api.historyRequests, isEmpty);
    expect(find.byType(ImportedHistoryScreen), findsNothing);
  });

  testWidgets('unrecorded dates drill into only originals without dates', (
    t,
  ) async {
    final api = OriginalReportApi();
    addTearDown(api.close);
    await showReport(t, api, filters: {'party': 'Customer 00'});
    final unrecorded = find.widgetWithText(TextButton, 'Unrecorded');
    await reveal(t, unrecorded);
    await t.tap(unrecorded);
    await t.pumpAndSettle();
    expect(api.historyRequests.last.$3, {
      'party': 'Customer 00',
      'date_basis': 'no_original',
    });
  });

  testWidgets('access removal clears already displayed original sums', (
    t,
  ) async {
    final api = OriginalReportApi();
    addTearDown(api.close);
    await showReport(t, api);
    expect(find.text('0.123456789'), findsOneWidget);
    api.access('Archive One', false, 'after');
    await t.pumpAndSettle();
    expect(find.text('0.123456789'), findsNothing);
    expect(
      find.textContaining('Your access to original production changed'),
      findsOneWidget,
    );
  });

  testWidgets(
    'applying original date filters resets page and keeps selected group',
    (t) async {
      final api = OriginalReportApi();
      addTearDown(api.close);
      await showReport(t, api);
      await reveal(t, find.text('Next groups'));
      await t.tap(find.text('Next groups'));
      await t.pumpAndSettle();
      await reveal(t, find.text('Filter records'), upward: true);
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('history-from-date')),
        '2024-01-01',
      );
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.requests.last.$3, 0);
      expect(api.requests.last.$4, {
        'date_basis': 'original',
        'from_date': '2024-01-01',
      });
    },
  );

  testWidgets('access removal hides results and cannot accept late responses', (
    t,
  ) async {
    final api = OriginalReportApi()
      ..delayed = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: OriginalProductionReport(api: api, company: 'Archive One'),
      ),
    );
    await t.pump();
    api.access('Archive One', false, 'after');
    await t.pumpAndSettle();
    api.delayed!.complete(api.page('Archive One', 'original_date', 0));
    await t.pumpAndSettle();
    expect(find.text('0.123456789'), findsNothing);
    expect(
      find.textContaining('Your access to original production changed'),
      findsOneWidget,
    );
  });

  testWidgets(
    'company changes reject an older company response and reset filters',
    (t) async {
      final api = OriginalReportApi()
        ..delayed = Completer<Map<String, dynamic>>();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: OriginalProductionReport(
            api: api,
            company: 'Archive One',
            initialFilters: const {'party': 'First'},
          ),
        ),
      );
      await t.pump();
      api.access('Archive Two', true, 'second');
      await showReport(t, api, company: 'Archive Two');
      api.delayed!.complete({
        ...api.page('Archive One', 'original_date', 0),
        'rows': <Map<String, dynamic>>[],
      });
      await t.pumpAndSettle();
      expect(api.requests.last.$1, 'Archive Two');
      expect(api.requests.last.$4, isEmpty);
      expect(find.text('0.123456789'), findsOneWidget);
      expect(find.text('Archive Two'), findsOneWidget);
    },
  );

  testWidgets('wrong report scope never exposes cached totals', (t) async {
    final api = OriginalReportApi()..wrongScope = true;
    addTearDown(api.close);
    await showReport(t, api);
    expect(find.text('0.123456789'), findsNothing);
    expect(find.textContaining('unexpected scope'), findsOneWidget);
  });

  testWidgets(
    'report fits a short phone with large text and exposes pagination',
    (t) async {
      t.view.physicalSize = const Size(360, 510);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = OriginalReportApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: OriginalProductionReport(api: api, company: 'Archive One'),
        ),
      );
      await t.pumpAndSettle();
      await reveal(t, find.text('Next groups'));
      expect(find.text('Next groups').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'original history and native reports expose scoped report entry',
    (t) async {
      final api = OriginalReportApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: ImportedHistoryScreen(
            api: api,
            company: 'Archive One',
            initialFamily: 'production',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Original production reports'));
      await t.pumpAndSettle();
      expect(find.byType(OriginalProductionReport), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Archive One',
              financialRead: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Original production reports'), findsOneWidget);
      api.access('Archive One', false, 'denied');
      await t.pumpAndSettle();
      expect(
        find.text('Original production reports').hitTestable(),
        findsNothing,
      );
    },
  );
}
