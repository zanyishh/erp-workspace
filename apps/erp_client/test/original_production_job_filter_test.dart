import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/original_production_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'original_production_report_test.dart' show OriginalReportApi, reveal;

class ProductionJobApi extends OriginalReportApi {
  final choices = <(String, String, int, Map<String, dynamic>)>[];
  Completer<Map<String, dynamic>>? pendingChoices;
  bool invalidLabels = false;
  Map<String, dynamic> labels(Map<String, dynamic> filters) => {
    if (filters.containsKey('source_job'))
      'source_job': invalidLabels ? {'raw': 'Hidden'} : '456/26',
  };
  @override
  Map<String, dynamic> page(String company, String group, int start) => {
    ...super.page(company, group, start),
    'available_filters': ['source_job', 'job', 'party', 'machine'],
    'filter_labels': labels(requests.last.$4),
  };
  @override
  Future<Map<String, dynamic>> importedHistoryRecords(
    String company,
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async => {
    ...await super.importedHistoryRecords(
      company,
      family,
      query: query,
      start: start,
      pageLength: pageLength,
      filters: filters,
    ),
    'available_filters': ['source_job', 'job', 'party', 'machine'],
    'filter_labels': labels(filters),
  };
  Map<String, dynamic> choicePage(String company, int start) => {
    'version': 1,
    'company': company,
    'family': 'production',
    'field': 'source_job',
    'start': start,
    'has_more': start == 0,
    'rows': [
      {
        'value': start == 0 ? '77' : '88',
        'label': start == 0 ? '456/26' : '789/25',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> importedHistoryFilterOptions(
    String company,
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  }) async {
    choices.add((company, field, start, Map.from(filters)));
    return pendingChoices == null
        ? choicePage(company, start)
        : pendingChoices!.future;
  }
}

Future<void> report(
  WidgetTester t,
  ProductionJobApi api, {
  Map<String, dynamic> filters = const {},
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: OriginalProductionReport(
        api: api,
        company: 'Archive One',
        initialFilters: filters,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> openJobChoices(WidgetTester t) async {
  await reveal(t, find.text('Filter records'), upward: true);
  await t.tap(find.text('Filter records'));
  await t.pumpAndSettle();
  await t.tap(find.text('Job order'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'job chooser pagination stays reachable on a short phone with larger text',
    (t) async {
      t.view.physicalSize = const Size(360, 510);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = ProductionJobApi();
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
      await reveal(t, find.text('Filter records'));
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Job order')),
        alignment: 0.5,
      );
      await t.pumpAndSettle();
      expect(find.text('Job order').hitTestable(), findsOneWidget);
      await t.tap(find.text('Job order'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('456/26').hitTestable(), findsOneWidget);
      expect(find.text('Next choices').hitTestable(), findsOneWidget);
      await t.tap(find.text('Next choices'));
      await t.pumpAndSettle();
      expect(api.choices.last.$3, 50);
    },
  );

  testWidgets(
    'report and drilldown show verified job label while carrying exact saved identity',
    (t) async {
      final api = ProductionJobApi();
      addTearDown(api.close);
      await report(t, api, filters: {'source_job': '77', 'machine': '00'});
      expect(find.textContaining('Job order: 456/26'), findsOneWidget);
      expect(find.textContaining('source_job'), findsNothing);
      expect(find.textContaining('Job order: 77'), findsNothing);
      await reveal(t, find.text('2024-04-05'));
      await t.tap(find.text('2024-04-05'));
      await t.pumpAndSettle();
      expect(api.historyRequests.last.$3, {
        'source_job': '77',
        'machine': '00',
        'date_basis': 'original',
        'from_date': '2024-04-05',
        'to_date': '2024-04-05',
      });
      expect(find.textContaining('Job order: 456/26'), findsOneWidget);
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      expect(find.text('Job order: 456/26'), findsOneWidget);
      expect(find.text('Original order value'), findsOneWidget);
    },
  );
  testWidgets(
    'job selection keeps its label and resets paging without replacing legacy filters',
    (t) async {
      final api = ProductionJobApi();
      addTearDown(api.close);
      await report(t, api, filters: {'job': 'raw-old', 'party': 'Same party'});
      await reveal(t, find.text('Next groups'));
      await t.tap(find.text('Next groups'));
      await t.pumpAndSettle();
      expect(api.requests.last.$3, 100);
      await openJobChoices(t);
      expect(api.choices.single.$4, {'job': 'raw-old', 'party': 'Same party'});
      await t.tap(find.text('456/26'));
      await t.pumpAndSettle();
      expect(find.text('Job order: 456/26'), findsOneWidget);
      expect(find.text('Job order: 77'), findsNothing);
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.requests.last.$3, 0);
      expect(api.requests.last.$4, {
        'job': 'raw-old',
        'party': 'Same party',
        'source_job': '77',
      });
      expect(find.textContaining('Job order: 456/26'), findsOneWidget);
    },
  );
  testWidgets('job choices page and clear only the source identity selector', (
    t,
  ) async {
    final api = ProductionJobApi();
    addTearDown(api.close);
    await report(t, api, filters: {'machine': '00'});
    await openJobChoices(t);
    await t.tap(find.text('Next choices'));
    await t.pumpAndSettle();
    expect(api.choices.last.$3, 50);
    expect(api.choices.last.$4, {'machine': '00'});
    await t.tap(find.text('789/25'));
    await t.pumpAndSettle();
    expect(find.text('Job order: 789/25'), findsOneWidget);
    await t.tap(find.byTooltip('Clear Job order'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    expect(api.requests.last.$4, {'machine': '00'});
  });
  testWidgets('late source-job choices cannot survive revoked history access', (
    t,
  ) async {
    final api = ProductionJobApi()
      ..pendingChoices = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await report(t, api);
    await t.tap(find.text('Filter records'));
    await t.pumpAndSettle();
    await t.tap(find.text('Job order'));
    await t.pump();
    api.access('Archive One', false, 'revoked');
    await t.pumpAndSettle();
    api.pendingChoices!.complete(api.choicePage('Archive One', 0));
    await t.pumpAndSettle();
    expect(find.text('456/26'), findsNothing);
    expect(find.textContaining('Your history access changed'), findsOneWidget);
    expect(api.requests.length, 1);
  });
  testWidgets(
    'malformed job display labels fail closed without exposing identity or totals',
    (t) async {
      final api = ProductionJobApi()..invalidLabels = true;
      addTearDown(api.close);
      await report(t, api, filters: {'source_job': '77'});
      expect(find.textContaining('unexpected format'), findsOneWidget);
      expect(find.text('0.123456789'), findsNothing);
      expect(find.textContaining('Job order: 77'), findsNothing);
      expect(find.textContaining('Hidden'), findsNothing);
    },
  );
  testWidgets(
    'company changes discard selected source-job label and identity',
    (t) async {
      final api = ProductionJobApi();
      addTearDown(api.close);
      await report(t, api, filters: {'source_job': '77'});
      expect(find.textContaining('Job order: 456/26'), findsOneWidget);
      api.access('Archive Two', true, 'changed');
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: OriginalProductionReport(api: api, company: 'Archive Two'),
        ),
      );
      await t.pumpAndSettle();
      expect(api.requests.last.$1, 'Archive Two');
      expect(api.requests.last.$4, isEmpty);
      expect(find.textContaining('456/26'), findsNothing);
    },
  );
}
