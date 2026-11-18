import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/report_screen.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_reports.dart';

class _ReportApi extends ErpApi {
  _ReportApi() : super(Uri.parse('http://localhost:8081'));
  var conditional = false;
  var analysis = false;
  bool prepared = false;
  Map<String, dynamic>? queuedFilters;
  @override
  Future<void> queueReport(String name, Map<String, dynamic> filters) async {
    queuedFilters = Map.of(filters);
    prepared = false;
  }

  Map<String, dynamic>? lastFilters;
  Completer<NativeReportResult>? pending;
  @override
  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) async => {
    'doctype': 'Report',
    'reference': 'Sales Invoice',
    'can_export': true,
    'fields': [
      {'fieldname': 'party', 'fieldtype': 'Data', 'label': 'Party'},
      if (analysis) ...[
        {
          'fieldname': 'status',
          'fieldtype': 'MultiSelectList',
          'label': 'Status',
          'options': 'Open\nCompleted',
        },
        {
          'fieldname': 'party_type',
          'fieldtype': 'Select',
          'label': 'Party type',
          'options': 'Customer\nSupplier',
        },
        {
          'fieldname': 'people',
          'fieldtype': 'MultiSelectList',
          'label': 'People',
          'options': 'party_type',
        },
      ],
      if (conditional) ...[
        {
          'fieldname': 'limit',
          'fieldtype': 'Int',
          'label': 'Limit',
          'conditions': {
            'depends_on': {'op': 'field', 'name': 'party'},
          },
        },
        {
          'fieldname': 'periodicity',
          'fieldtype': 'Data',
          'label': 'Periodicity',
          'hidden': 1,
        },
      ],
    ],
    if (analysis)
      'defaults': {
        'party_type': 'Customer',
        'people': ['Blue Mill'],
      },
    if (conditional) 'defaults': {'party': 'Mill', 'periodicity': 'Yearly'},
  };

  @override
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async {
    lastFilters = filters;
    if (pending != null) return pending!.future;
    if (prepared) return NativeReportResult.fromJson({'prepared_report': true});
    return NativeReportResult.fromJson({
      if (analysis)
        'chart': {
          'type': 'donut',
          'title': 'Order amounts',
          'data': {
            'labels': ['Amount to Bill', 'Billed Amount'],
            'datasets': [
              {
                'values': [25, 75],
              },
            ],
          },
        },
      'columns': [
        {'fieldname': 'party', 'label': 'Party'},
      ],
      'result': [
        {'party': filters['party'] ?? 'All customers'},
      ],
    });
  }
}

void main() {
  testWidgets(
    'prepared report uses the requested filters while retaining the applied result',
    (t) async {
      final api = _ReportApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Sales Register'),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Blue Mill');
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      api.prepared = true;
      await t.enterText(find.byType(TextFormField), 'Green Mill');
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      expect(find.text('Blue Mill'), findsOneWidget);
      expect(
        find.textContaining('Applied filters: Party: Blue Mill'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextFormField), 'Red Mill');
      await t.ensureVisible(find.text('Generate report'));
      await t.tap(find.text('Generate report'));
      await t.pumpAndSettle();
      expect(api.queuedFilters, {'party': 'Green Mill'});
      expect(find.text('Green Mill'), findsOneWidget);
      expect(
        find.textContaining('Applied filters: Party: Green Mill'),
        findsOneWidget,
      );
      expect(find.textContaining('Filters changed'), findsOneWidget);
    },
  );

  testWidgets('a superseded report cannot replace the newer applied result', (
    t,
  ) async {
    final api = _ReportApi();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: NativeReportScreen(api: api, name: 'Sales Register'),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Old request');
    final slow = Completer<NativeReportResult>();
    api.pending = slow;
    await t.tap(find.text('Run report'));
    await t.pump();
    await t.enterText(find.byType(TextFormField), 'Latest request');
    api.pending = null;
    await t.tap(find.text('Run report'));
    await t.pumpAndSettle();
    slow.complete(
      NativeReportResult.fromJson({
        'columns': [
          {'fieldname': 'party', 'label': 'Party'},
        ],
        'result': [
          {'party': 'Obsolete result'},
        ],
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('Obsolete result'), findsNothing);
    expect(
      find.textContaining('Applied filters: Party: Latest request'),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed rerun keeps the prior applied result and filter summary',
    (t) async {
      final api = _ReportApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Sales Register'),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Blue Mill');
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Green Mill');
      api.pending = Completer<NativeReportResult>();
      await t.tap(find.text('Run report'));
      await t.pump();
      expect(find.text('Blue Mill'), findsOneWidget);
      expect(
        find.textContaining('Applied filters: Party: Blue Mill'),
        findsOneWidget,
      );
      api.pending!.completeError(const FormatException('Report unavailable'));
      await t.pumpAndSettle();
      expect(find.text('Blue Mill'), findsOneWidget);
      expect(
        find.textContaining('Applied filters: Party: Blue Mill'),
        findsOneWidget,
      );
      expect(find.textContaining('Report unavailable'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
    },
  );

  testWidgets(
    'order analysis plots its chart, selects statuses and clears stale party choices',
    (t) async {
      final api = _ReportApi()..analysis = true;
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Sales Order Analysis'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Find Status'));
      await t.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      await t.tap(find.text('Completed'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Supplier').last);
      await t.pumpAndSettle();
      expect(find.text('Blue Mill'), findsNothing);
      await t.ensureVisible(find.text('Run report'));
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      expect(api.lastFilters?['status'], ['Completed']);
      expect(api.lastFilters?['people'], isEmpty);
      expect(find.text('Order amounts'), findsOneWidget);
      expect(find.text('Amount to Bill'), findsOneWidget);
      await t.ensureVisible(find.byTooltip('Next chart value'));
      await t.tap(find.byTooltip('Next chart value'));
      await t.pumpAndSettle();
      expect(find.text('Billed Amount'), findsOneWidget);
      expect(find.text('75'), findsOneWidget);
    },
  );

  testWidgets(
    'hiding a conditional filter drops its invalid value and keeps fixed defaults',
    (tester) async {
      final api = _ReportApi()..conditional = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Financial Ratios'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Limit'),
        'oops',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Party'), '');
      await tester.pumpAndSettle();
      expect(find.text('Limit'), findsNothing);
      await tester.tap(find.text('Run report'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(api.lastFilters, {'periodicity': 'Yearly'});
    },
  );

  testWidgets(
    'report links open native records and preserve displayed amounts',
    (tester) async {
      final result = NativeReportResult.fromJson({
        'columns': [
          {
            'fieldname': 'account',
            'label': 'Account',
            'fieldtype': 'Link',
            'options': 'Account',
          },
          {'fieldname': 'debit', 'label': 'Debit', 'fieldtype': 'Currency'},
        ],
        'result': [
          {'account': 'Cash', 'debit': 125.5},
        ],
      });
      (String, String)? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeReportTable(
              result: result,
              onDocument: (type, name) => selected = (type, name),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('125.5'), findsOneWidget);
      await tester.tap(find.text('Cash'));
      expect(selected, ('Account', 'Cash'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing report filters retains applied rows and exports until successful rerun',
    (tester) async {
      final api = _ReportApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Sales Register'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run report'));
      await tester.pumpAndSettle();
      expect(find.text('All customers'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Blue Mill');
      await tester.pumpAndSettle();
      expect(find.text('All customers'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.textContaining('Filters changed'), findsOneWidget);
      String? copied;
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.ensureVisible(find.text('Copy CSV'));
      await tester.tap(find.text('Copy CSV'));
      expect(copied, contains('All customers'));
      expect(copied, isNot(contains('Blue Mill')));
      await tester.ensureVisible(find.text('Run report'));
      await tester.tap(find.text('Run report'));
      await tester.pumpAndSettle();
      expect(find.text('Blue Mill'), findsWidgets);
      expect(find.text('All customers'), findsNothing);
      expect(find.textContaining('Filters changed'), findsNothing);
      expect(
        find.textContaining('Applied filters: Party: Blue Mill'),
        findsOneWidget,
      );
    },
  );
}
