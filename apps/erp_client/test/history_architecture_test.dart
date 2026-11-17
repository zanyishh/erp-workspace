import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/imported_history/data/erp_history_repository.dart';
import 'package:erp_client/features/imported_history/data/history_repository.dart';
import 'package:erp_client/features/imported_history/models/history_models.dart';
import 'package:erp_client/features/imported_history/presentation/history_register_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/history_detail_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/original_production_view_model.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> historySummary({
  String company = 'A',
  bool shared = true,
}) => {
  'version': 1,
  'company': company,
  'families': [
    {'key': 'job', 'label': 'Jobs', 'count': 1},
  ],
  'shared_cash_available': shared,
};
Map<String, dynamic> historyPage({
  String company = 'A',
  String family = 'job',
  int start = 0,
  int length = 40,
}) => {
  'version': 1,
  'company': company,
  'family': family,
  'start': start,
  'page_length': length,
  'row_count': 81,
  'has_more': start < 80,
  'available_filters': ['source_book', 'source_job'],
  'rows': [
    {
      'name': '$family-$start',
      'family': family,
      'title': 'Original $start',
      'summary': 'Synthetic',
      'nested': {
        'values': ['original'],
      },
    },
  ],
  if (family == 'shared_cash') ...{
    'balances': [
      {'cash_book_id': '0', 'label': 'Cash', 'verified': false},
    ],
    'shared_scope': {
      'cash_is_shared': true,
      'companies': ['A', 'B'],
    },
  },
};
Map<String, dynamic> historyDetail({
  String company = 'A',
  String name = 'history-1',
}) => {
  'version': 1,
  'company': company,
  'name': name,
  'family': 'job',
  'title': 'Original job',
  'fields': [
    {'label': 'Original quantity', 'value': '-0.1250'},
  ],
  'tables': [
    {
      'title': 'Masked table',
      'columns': [],
      'rows': [{}],
    },
  ],
  'review_notes': ['Original date not recorded'],
  'target_links': [],
};
Map<String, dynamic> productionPage({
  String company = 'A',
  String group = 'original_date',
  int start = 0,
}) => {
  'version': 1,
  'company': company,
  'family': 'production',
  'group_by': group,
  'start': start,
  'page_length': 100,
  'row_count': 101,
  'has_more': start == 0,
  'available_filters': ['machine', 'source_job'],
  'totals': {
    'source_record_count': 2,
    'quantity_kg': '-0.1250',
    'recorded_count': null,
    'missing_quantity_rows': 0,
    'missing_count_rows': 2,
  },
  'rows': [
    {
      'label': 'Saved machine',
      'value': 'Saved machine',
      'drillable': true,
      'filters': {'machine': 'Saved machine'},
      'source_record_count': 2,
      'quantity_kg': '-0.1250',
      'recorded_count': null,
      'missing_quantity_rows': 0,
      'missing_count_rows': 2,
    },
  ],
};
Map<String, dynamic> historyOptions({
  String company = 'A',
  String family = 'job',
  String field = 'source_book',
  int start = 0,
}) => {
  'version': 1,
  'company': company,
  'family': family,
  'field': field,
  'start': start,
  'has_more': true,
  'rows': [
    {
      'value': field == 'source_book' ? null : 'source-job-1',
      'label': 'Original choice',
    },
  ],
};
Map<String, dynamic> originalPrint({
  String company = 'A',
  String name = 'history-1',
}) => {
  'version': 1,
  'company': company,
  'source_record': name,
  'source_copy': true,
  'document_label': 'Orders',
  'title': 'Original order',
  'reference': 'ORDER-1',
  'fields': [
    {'label': 'Original quantity', 'value': '-0.1250'},
  ],
  'tables': [],
  'review_notes': [],
};

class MemoryHistoryRepository implements ImportedHistoryRepository {
  @override
  Object identity = Object();
  @override
  Object? scope = 1;
  @override
  bool canReadProduction = true;
  Map<String, dynamic> summaryData = historySummary();
  Completer<HistorySummary>? pendingSummary;
  Completer<HistoryPage>? pendingPage;
  Completer<HistoryDetail>? pendingDetail;
  Completer<OriginalProductionPage>? pendingProduction;
  final calls = <(String, String, int, Map<String, dynamic>)>[];
  @override
  Future<HistorySummary> summary() =>
      pendingSummary?.future ??
      Future.value(HistorySummary.fromJson(summaryData, company: 'A'));
  @override
  Future<HistoryPage> records(
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) {
    calls.add(('records', family, start, filters));
    return pendingPage?.future ??
        Future.value(
          HistoryPage.fromJson(
            historyPage(family: family, start: start, length: pageLength),
            company: 'A',
            family: family,
            start: start,
            pageLength: pageLength,
            filters: filters,
          ),
        );
  }

  @override
  Future<HistoryDetail> detail(String name) =>
      pendingDetail?.future ??
      Future.value(
        HistoryDetail.fromJson(
          historyDetail(name: name),
          company: 'A',
          name: name,
        ),
      );
  @override
  Future<OriginalProductionPage> production({
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  }) {
    calls.add(('production', groupBy, start, filters));
    return pendingProduction?.future ??
        Future.value(
          OriginalProductionPage.fromJson(
            productionPage(group: groupBy, start: start),
            company: 'A',
            groupBy: groupBy,
            start: start,
            pageLength: pageLength,
            filters: filters,
          ),
        );
  }

  @override
  Future<HistoryChoicesPage> options(
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  }) async => HistoryChoicesPage.fromJson(
    historyOptions(family: family, field: field, start: start),
    company: 'A',
    family: family,
    field: field,
    start: start,
  );
  @override
  Future<OriginalRecordData> printData(String name) async =>
      OriginalRecordData.fromJson(
        originalPrint(name: name),
        company: 'A',
        name: name,
      );
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081')) {
    publishContext(
      WorkspaceContext.fromJson({
        'company': 'A',
        'can_read_imported_history': true,
      }),
    );
  }
  Completer<Map<String, dynamic>>? pendingSummary;
  final calls = <(String, String, String, String, int, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> importedHistorySummary(String company) =>
      pendingSummary?.future ?? Future.value(historySummary(company: company));
  @override
  Future<Map<String, dynamic>> importedHistoryRecords(
    String company,
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async {
    calls.add(('records', company, family, query, start, filters));
    return historyPage(
      company: company,
      family: family,
      start: start,
      length: pageLength,
    );
  }

  @override
  Future<Map<String, dynamic>> importedSharedCash(
    String company, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async {
    calls.add(('cash', company, 'shared_cash', query, start, filters));
    return historyPage(
      company: company,
      family: 'shared_cash',
      start: start,
      length: pageLength,
    );
  }
}

void main() {
  test('history response values freeze nested read data and preserve masked tables', () {
    final raw = historyPage();
    final page = HistoryPage.fromJson(
      raw,
      company: 'A',
      family: 'job',
      start: 0,
      pageLength: 40,
      filters: {},
    );
    (raw['rows'] as List).clear();
    expect(page.rows, hasLength(1));
    expect(() => page.rows.single['title'] = 'changed', throwsUnsupportedError);
    expect(
      () => ((page.rows.single['nested'] as Map)['values'] as List).clear(),
      throwsUnsupportedError,
    );
    final detail = HistoryDetail.fromJson(
      historyDetail(),
      company: 'A',
      name: 'history-1',
    );
    expect((detail.data['fields'] as List).single['value'], '-0.1250');
    expect(
      () => ((detail.data['tables'] as List).single as Map).clear(),
      throwsUnsupportedError,
    );
  });
  for (final mutation in ['scope', 'duplicate', 'page', 'labels', 'cash']) {
    test('history page rejects malformed $mutation responses', () {
      final family = mutation == 'cash' ? 'shared_cash' : 'job';
      final raw = historyPage(family: family);
      switch (mutation) {
        case 'scope':
          raw['company'] = 'B';
        case 'duplicate':
          (raw['rows'] as List).add((raw['rows'] as List).first);
        case 'page':
          raw['start'] = 40;
        case 'labels':
          raw['filter_labels'] = {'source_job': 'Unexpected unrequested label'};
        default:
          raw['balances'] = [
            {'cash_book_id': '0', 'label': 'Cash', 'verified': 'yes'},
          ];
      }
      expect(
        () => HistoryPage.fromJson(
          raw,
          company: 'A',
          family: family,
          start: 0,
          pageLength: 40,
          filters: {},
        ),
        throwsA(isA<ErpException>()),
      );
    });
  }
  test(
    'production preserves signed decimal text and validates missing counts',
    () {
      final raw = productionPage();
      final page = OriginalProductionPage.fromJson(
        raw,
        company: 'A',
        groupBy: 'original_date',
        start: 0,
        pageLength: 100,
        filters: {},
      );
      expect(page.totals['quantity_kg'], '-0.1250');
      expect(page.totals['recorded_count'], isNull);
      expect(() => page.totals.clear(), throwsUnsupportedError);
      (raw['totals'] as Map)['missing_count_rows'] = 3;
      expect(
        () => OriginalProductionPage.fromJson(
          raw,
          company: 'A',
          groupBy: 'original_date',
          start: 0,
          pageLength: 100,
          filters: {},
        ),
        throwsA(isA<ErpException>()),
      );
    },
  );
  test(
    'choice values retain null source books and reject missing job identity',
    () {
      final books = HistoryChoicesPage.fromJson(
        historyOptions(),
        company: 'A',
        family: 'job',
        field: 'source_book',
        start: 0,
      );
      expect(books.rows.single['value'], isNull);
      final raw = historyOptions(field: 'source_job');
      (raw['rows'] as List).single['value'] = '';
      expect(
        () => HistoryChoicesPage.fromJson(
          raw,
          company: 'A',
          family: 'job',
          field: 'source_job',
          start: 0,
        ),
        throwsA(isA<ErpException>()),
      );
    },
  );
  test('ERP history adapter keeps ordinary and shared cash endpoint payloads separate', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpImportedHistoryRepository(api: api, company: 'A');
    await repository.records(
      'job',
      query: 'Order',
      start: 40,
      filters: {'source_book': null},
    );
    await repository.records(
      'shared_cash',
      query: 'Cash',
      start: 80,
      filters: {'date_basis': 'no_original'},
    );
    expect(api.calls[0].$1, 'records');
    expect(api.calls[0].$2, 'A');
    expect(api.calls[0].$3, 'job');
    expect(api.calls[0].$4, 'Order');
    expect(api.calls[0].$5, 40);
    expect(api.calls[0].$6, {'source_book': null});
    expect(api.calls[1].$1, 'cash');
    expect(api.calls[1].$3, 'shared_cash');
    expect(api.calls[1].$4, 'Cash');
    expect(api.calls[1].$5, 80);
    expect(api.calls[1].$6, {'date_basis': 'no_original'});
  });
  for (final changed in ['account', 'revision', 'unready']) {
    test('ERP history reads reject a changed $changed', () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpImportedHistoryRepository(api: api, company: 'A');
      final waiting = Completer<Map<String, dynamic>>();
      api.pendingSummary = waiting;
      final result = repository.summary();
      final expectation = expectLater(result, throwsA(isA<ErpException>()));
      switch (changed) {
        case 'account':
          api.account = 'different@example.invalid';
        case 'revision':
          api.accessRevision++;
        default:
          api.accessReady = false;
      }
      waiting.complete(historySummary());
      await expectation;
    });
  }
  test(
    'register fallback, paging and family changes preserve state policy',
    () async {
      final repository = MemoryHistoryRepository();
      final model = HistoryRegisterViewModel(
        repository,
        initialFamily: 'missing',
        initialFilters: {'source_book': null},
      );
      addTearDown(model.dispose);
      await model.settled;
      expect(model.family, 'job');
      expect(repository.calls.single.$4, {'source_book': null});
      await model.nextPage();
      expect(model.start, 40);
      await model.chooseFamily('shared_cash');
      expect(model.start, 0);
      expect(model.filters, isEmpty);
      expect(model.family, 'shared_cash');
      expect(repository.calls.last.$2, 'shared_cash');
    },
  );
  test(
    'register search invalidates old rows before the debounce completes',
    () async {
      final repository = MemoryHistoryRepository();
      final model = HistoryRegisterViewModel(repository);
      addTearDown(model.dispose);
      await model.settled;
      final waiting = Completer<HistoryPage>();
      repository.pendingPage = waiting;
      final old = model.reload();
      model.beginSearch();
      waiting.complete(
        HistoryPage.fromJson(
          historyPage(),
          company: 'A',
          family: 'job',
          start: 0,
          pageLength: 40,
          filters: {},
        ),
      );
      await old;
      expect(model.rows, isEmpty);
      repository.pendingPage = null;
      await model.search(' latest ');
      expect(model.query, 'latest');
      expect(model.start, 0);
    },
  );
  test(
    'obsolete filter dialog results cannot change a replacement register view',
    () async {
      final repository = MemoryHistoryRepository();
      final model = HistoryRegisterViewModel(repository);
      addTearDown(model.dispose);
      await model.settled;
      final intent = model.prepareFilters();
      expect(intent, isNotNull);
      await model.chooseFamily('shared_cash');
      expect(await model.applyFilters(intent!, {'source_book': '0'}), isFalse);
      expect(model.filters, isEmpty);
    },
  );
  test('detail read rejects disposal before its completion', () async {
    final repository = MemoryHistoryRepository(),
        waiting = Completer<HistoryDetail>();
    repository.pendingDetail = waiting;
    final model = HistoryDetailViewModel(repository, name: 'history-1');
    final expectation = expectLater(model.result, throwsA(isA<ErpException>()));
    model.dispose();
    waiting.complete(
      HistoryDetail.fromJson(historyDetail(), company: 'A', name: 'history-1'),
    );
    await expectation;
  });
  test('production model keeps server totals, group changes reset page and read capability is enforced', () async {
    final repository = MemoryHistoryRepository();
    final model = OriginalProductionViewModel(repository);
    addTearDown(model.dispose);
    await model.settled;
    expect(model.totals!['quantity_kg'], '-0.1250');
    await model.nextPage();
    expect(model.start, 100);
    await model.chooseGroup('machine');
    expect(model.start, 0);
    expect(model.group, 'machine');
    repository.canReadProduction = false;
    await model.reload();
    expect(model.rows, isEmpty);
    expect(model.totals, isNull);
    expect(model.error, isNotNull);
  });
  test(
    'unready register and detail construction makes no data requests',
    () async {
      final repository = MemoryHistoryRepository()..scope = null;
      final register = HistoryRegisterViewModel(repository);
      addTearDown(register.dispose);
      final detail = HistoryDetailViewModel(repository, name: 'history-1');
      addTearDown(detail.dispose);
      await register.settled;
      await expectLater(detail.result, throwsA(isA<ErpException>()));
      expect(repository.calls, isEmpty);
      expect(register.rows, isEmpty);
    },
  );
}
