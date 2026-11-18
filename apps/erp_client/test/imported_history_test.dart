import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/imported_history.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class HistoryApi extends ErpApi {
  HistoryApi() : super(Uri.parse('http://127.0.0.1:8082'));
  bool wrongCompany = false, denied = false;
  Completer<Map<String, dynamic>>? delayed;
  bool emptyTable = false;
  Map<String, dynamic>? productionFields;
  String? productionReference;
  List<Map<String, dynamic>> cashBalances = [];
  final requests = <(String, String, int)>[];
  final filterRequests = <Map<String, dynamic>>[];
  final optionRequests = <(String, int)>[];
  Completer<Map<String, dynamic>>? delayedChoices;
  List<String> availableFilters = ['source_book', 'party', 'job', 'status'];
  @override
  Future<Map<String, dynamic>> importedHistorySummary(String company) async => {
    'version': 1,
    'company': company,
    'scope_available': true,
    'companies': [company],
    'families': [
      {'key': 'job', 'label': 'Jobs', 'count': 3},
      if (productionFields != null)
        {'key': 'production', 'label': 'Production', 'count': 1},
      if (!denied) {'key': 'invoice', 'label': 'Invoices', 'count': 1},
    ],
    'shared_cash_available': !denied,
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
    filterRequests.add(Map.from(filters));
    requests.add((family, query, start));
    if (query == 'slow' && delayed != null) return delayed!.future;
    if (denied && family == 'invoice') {
      throw const ErpException(
        'Financial access is unavailable.',
        permissionDenied: true,
      );
    }
    return {
      'version': 1,
      'company': wrongCompany ? 'Other Company' : company,
      'family': family,
      'start': start,
      'page_length': pageLength,
      'has_more': start == 0 && query.isEmpty && family == 'job',
      'row_count': 41,
      'available_filters': availableFilters,
      'rows': [
        {
          'name': 'history-$family-${start + 1}',
          'family': family,
          'reference': '$family-${start + 1}',
          'original_date': '2024-04-05',
          'effective_date': null,
          'date_basis': 'original',
          'review_status': 'Review needed',
          'title': 'Original $family ${start + 1}',
          'summary': 'Fixture Customer · 12.5 kg',
          if (family == 'production' && productionFields != null)
            'production_fields': productionFields,
          if (family == 'production') 'native_id': '120',
          if (family == 'production' && productionReference != null)
            'job_reference_display': productionReference,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> importedHistoryDetail(
    String company,
    String name,
  ) async {
    if (denied) {
      throw const ErpException(
        'Financial access is unavailable.',
        permissionDenied: true,
      );
    }
    return {
      'version': 1,
      'company': company,
      'name': name,
      'family': 'job',
      'reference': 'JOB-24',
      'title': 'Original programme',
      'original_date': null,
      'effective_date': '2023-04-01',
      'date_basis': 'approved_opening',
      'review_status': 'Review needed',
      'fields': [
        {'label': 'Party', 'value': 'Fixture Customer'},
      ],
      'tables': [
        {
          'title': 'Fabric quantities',
          if (emptyTable) ...{
            'columns': [],
            'rows': [],
          } else ...{
            'columns': [
              {'key': 'description', 'label': 'Fabric'},
              {'key': 'quantity', 'label': 'Quantity'},
            ],
            'rows': [
              {'description': 'Test fabric', 'quantity': '12.500 kg'},
            ],
          },
        },
      ],
      'review_notes': ['The original date was not recorded.'],
      'target_links': [
        {'doctype': 'Journal Entry', 'name': 'Synthetic-JV-1'},
      ],
      'printable': false,
      'print_reason': 'Printing is unavailable for this record.',
    };
  }

  @override
  Future<Map<String, dynamic>> importedSharedCash(
    String company, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async => {
    'version': 1,
    'company': company,
    'family': 'shared_cash',
    'start': start,
    'page_length': pageLength,
    'has_more': false,
    'balances': cashBalances,
    'shared_scope': {
      'name': 'Shared cash',
      'companies': ['Archive One', 'Archive Two'],
      'cash_is_shared': true,
    },
    'rows': [],
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
    optionRequests.add((field, start));
    if (query == 'slow' && delayedChoices != null) {
      return delayedChoices!.future;
    }
    return {
      'version': 1,
      'company': company,
      'family': family,
      'field': field,
      'start': start,
      'has_more': start == 0,
      'rows': [
        {
          'value': start == 0 ? 'Visible name' : 'Older name',
          'label': start == 0 ? 'Visible name' : 'Older name',
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'original production exposes saved columns and opens its record',
    (t) async {
      final api = HistoryApi()
        ..productionFields = {
          'job': 'J-11',
          'party': 'Fixture Mill',
          'description': 'Rib fabric',
          'dia': '38',
          'shift': 'Night',
          'machine': '07',
          'operator': 'Fixture Operator',
          'rolls': '0',
          'net_kg': '-0.200',
        }
        ..productionReference = 'J-11/26'
        ..availableFilters = ['source_book', 'party', 'job', 'shift'];
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
      expect(find.text('Rib fabric'), findsOneWidget);
      expect(find.text('J-11/26'), findsOneWidget);
      expect(api.productionFields!['job'], 'J-11');
      expect(find.text('07'), findsOneWidget);
      expect(find.text('Fixture Operator'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('-0.200'), findsOneWidget);
      expect(find.text('2024-04-05'), findsOneWidget);
      expect(find.text('Shift'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      final open = find.byTooltip('View original production 120');
      await t.ensureVisible(open);
      await t.tap(open);
      await t.pumpAndSettle();
      expect(find.text('Original programme'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('production shift filter submits the exact saved shift', (
    t,
  ) async {
    final api = HistoryApi()
      ..productionFields = {}
      ..availableFilters = ['shift'];
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
    await t.tap(find.text('Filter records'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, 'Shift'));
    await t.pumpAndSettle();
    await t.tap(find.text('Visible name'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    expect(api.filterRequests.last, {'shift': 'Visible name'});
    expect(api.optionRequests.last.$1, 'shift');
    expect(find.textContaining('Shift: Visible name'), findsOneWidget);
  });

  testWidgets('production dimensions expose exact saved employee filters', (
    t,
  ) async {
    final api = HistoryApi()
      ..productionFields = {'operator': 'Visible name', 'dia': '0'}
      ..availableFilters = ['machine', 'operator', 'description', 'dia'];
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
    await t.tap(find.text('Filter records'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Machine'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Employee / operator'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Fabric'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Dia / size'), findsOneWidget);
    await t.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Employee / operator'),
    );
    await t.tap(find.widgetWithText(OutlinedButton, 'Employee / operator'));
    await t.pumpAndSettle();
    await t.tap(find.text('Visible name').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Apply filters'));
    await t.pumpAndSettle();
    expect(api.filterRequests.last['operator'], 'Visible name');
    expect(
      find.textContaining('Employee / operator: Visible name'),
      findsOneWidget,
    );
  });

  testWidgets(
    'history choice search rejects stale results and access revocation clears choices',
    (t) async {
      final api = HistoryApi()
        ..delayedChoices = Completer<Map<String, dynamic>>();
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Archive One',
          'access_fingerprint': 'before',
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: ImportedHistoryScreen(api: api, company: 'Archive One'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Original party name'));
      await t.tap(find.text('Original party name'));
      await t.pumpAndSettle();
      final input = find.widgetWithText(TextField, 'Search saved values');
      await t.enterText(input, 'slow');
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(input, 'current');
      await t.pumpAndSettle();
      api.delayedChoices!.complete({
        'version': 1,
        'company': 'Archive One',
        'family': 'job',
        'field': 'party',
        'start': 0,
        'has_more': false,
        'rows': [
          {'value': 'STALE', 'label': 'STALE'},
        ],
      });
      await t.pumpAndSettle();
      expect(find.text('STALE'), findsNothing);
      expect(find.text('Visible name'), findsOneWidget);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Archive One',
          'access_fingerprint': 'after',
        }),
      );
      await t.pumpAndSettle();
      expect(find.text('Visible name'), findsNothing);
      expect(
        find.text('Your history access changed. Reopen the filters.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'history company and family changes clear applied filters and absent fields stay hidden',
    (t) async {
      final api = HistoryApi()..availableFilters = ['source_book'];
      addTearDown(api.close);
      Future<void> showCompany(String company) async {
        await t.pumpWidget(
          MaterialApp(
            home: ImportedHistoryScreen(api: api, company: company),
          ),
        );
        await t.pumpAndSettle();
      }

      Future<void> applyUndated() async {
        await t.tap(find.text('Filter records'));
        await t.pumpAndSettle();
        expect(find.text('Original party name'), findsNothing);
        await t.tap(find.text('All dates'));
        await t.pumpAndSettle();
        await t.tap(find.text('No original date').last);
        await t.pumpAndSettle();
        await t.tap(find.text('Apply filters'));
        await t.pumpAndSettle();
      }

      await showCompany('Archive One');
      await applyUndated();
      await t.tap(find.text('Jobs · 3 total'));
      await t.pumpAndSettle();
      await t.tap(find.text('Invoices · 1 total').last);
      await t.pumpAndSettle();
      expect(api.filterRequests.last, isEmpty);
      expect(api.requests.last.$1, 'invoice');
      await applyUndated();
      await showCompany('Archive Two');
      expect(api.filterRequests.last, isEmpty);
      expect(api.requests.last.$3, 0);
      expect(find.textContaining('Applied:'), findsNothing);
    },
  );
  testWidgets(
    'history filters apply exact original values and keep paging scoped',
    (t) async {
      final api = HistoryApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: ImportedHistoryScreen(api: api, company: 'Archive One'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('history-from-date')),
        '2026-11-01',
      );
      await t.ensureVisible(find.text('Original party name'));
      await t.tap(find.text('Original party name'));
      await t.pumpAndSettle();
      await t.tap(find.text('Next choices'));
      await t.pumpAndSettle();
      await t.tap(find.text('Older name'));
      await t.pumpAndSettle();
      expect(api.filterRequests.last, isEmpty);
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.filterRequests.last, {
        'date_basis': 'original',
        'from_date': '2026-11-01',
        'party': 'Older name',
      });
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(api.requests.last.$3, 40);
      expect(api.filterRequests.last['party'], 'Older name');
      await t.tap(find.text('Clear filters'));
      await t.pumpAndSettle();
      expect(api.filterRequests.last, isEmpty);
      expect(api.requests.last.$3, 0);
      expect(api.optionRequests, contains(('party', 50)));
    },
  );

  testWidgets(
    'history filters fit a short phone and no-original date clears ranges',
    (t) async {
      final api = HistoryApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(360, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: ImportedHistoryScreen(api: api, company: 'Archive One'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Filter records'));
      await t.pumpAndSettle();
      await t.tap(find.text('All dates'));
      await t.pumpAndSettle();
      await t.tap(find.text('No original date').last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-from-date')), findsNothing);
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.filterRequests.last, {'date_basis': 'no_original'});
      expect(t.takeException(), isNull);
    },
  );
  Future<void> show(WidgetTester t, HistoryApi api, {String? family}) async {
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: ImportedHistoryScreen(
          api: api,
          company: 'Archive One',
          initialFamily: family,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'shared source controls show exact signed totals once with their review status',
    (t) async {
      final api = HistoryApi()
        ..cashBalances = [
          {
            'cash_book_id': '1',
            'label': 'Shared expenses',
            'opening_net': '-12.50',
            'movement_debit': '4.25',
            'movement_credit': '1.00',
            'net': '-9.25',
            'verified': true,
            'as_of_date': '2026-11-14',
            'basis': 'Source category control',
          },
        ];
      await show(t, api, family: 'shared_cash');
      expect(find.text('Shared expenses'), findsOneWidget);
      expect(find.text('-12.50'), findsOneWidget);
      expect(find.text('-9.25'), findsOneWidget);
      expect(find.text('Source matched'), findsOneWidget);
      expect(find.textContaining('posted balance'), findsNothing);
    },
  );
  testWidgets(
    'missing shared cash controls stay unavailable instead of becoming zero',
    (t) async {
      final api = HistoryApi();
      await show(t, api, family: 'shared_cash');
      expect(
        find.text('Source balances are not available yet.'),
        findsOneWidget,
      );
      expect(find.text('0.00'), findsNothing);
    },
  );

  testWidgets(
    'an older search response cannot restore stale original records',
    (t) async {
      final api = HistoryApi()..delayed = Completer<Map<String, dynamic>>();
      await show(t, api);
      await t.enterText(find.byType(TextField), 'slow');
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField), 'current');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('Original job 1'), findsOneWidget);
      api.delayed!.complete({
        'version': 1,
        'company': 'Archive One',
        'family': 'job',
        'start': 0,
        'page_length': 40,
        'has_more': false,
        'rows': [
          {'name': 'old', 'family': 'job', 'title': 'Stale record'},
        ],
      });
      await t.pumpAndSettle();
      expect(find.text('Stale record'), findsNothing);
      expect(api.requests.last.$2, 'current');
    },
  );
  testWidgets('a preserved empty source table does not hide its header', (
    t,
  ) async {
    final api = HistoryApi()..emptyTable = true;
    await show(t, api);
    await t.tap(find.text('Original job 1'));
    await t.pumpAndSettle();
    expect(find.text('Original programme'), findsOneWidget);
    expect(find.text('No original lines recorded.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'original detail preserves unknown dates and returns to searched register',
    (t) async {
      final api = HistoryApi();
      await show(t, api);
      expect(find.text('Original job 1'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'JOB-24');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(api.requests.last, ('job', 'JOB-24', 0));
      await t.tap(find.text('Original job 1'));
      await t.pumpAndSettle();
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('2023-04-01'), findsOneWidget);
      expect(find.text('The original date was not recorded.'), findsOneWidget);
      expect(find.text('12.500 kg'), findsOneWidget);
      expect(find.text('Related ERP records'), findsOneWidget);
      expect(find.text('Synthetic-JV-1'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'JOB-24',
      );
      expect(find.text('Original job 1'), findsOneWidget);
    },
  );

  testWidgets(
    'pagination is bounded and shared cash is one workspace destination',
    (t) async {
      final api = HistoryApi();
      await show(t, api);
      await t.tap(find.widgetWithText(OutlinedButton, 'Next'));
      await t.pumpAndSettle();
      expect(api.requests.last, ('job', '', 40));
      expect(find.text('Original job 41'), findsOneWidget);
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Shared cash').last);
      await t.pumpAndSettle();
      expect(find.text('Shared across companies'), findsOneWidget);
      expect(find.text('No records in this view.'), findsOneWidget);
      expect(find.text('Original job 41'), findsNothing);
    },
  );

  testWidgets(
    'mismatched company page is rejected without showing its records',
    (t) async {
      await show(t, HistoryApi()..wrongCompany = true);
      expect(find.text('Original job 1'), findsNothing);
      expect(find.textContaining('unexpected scope'), findsOneWidget);
    },
  );

  testWidgets('financial family omitted by server is never requested', (
    t,
  ) async {
    final api = HistoryApi()..denied = true;
    await show(t, api, family: 'invoice');
    expect(api.requests.every((r) => r.$1 == 'job'), isTrue);
    expect(find.text('Original invoice 1'), findsNothing);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    expect(find.text('Invoices'), findsNothing);
    expect(find.text('Shared cash'), findsNothing);
  });

  testWidgets(
    'narrow history detail keeps quantities and back navigation reachable',
    (t) async {
      t.view.physicalSize = const Size(390, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await show(t, HistoryApi());
      await t.tap(find.text('Original job 1'));
      await t.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Fabric quantities'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
