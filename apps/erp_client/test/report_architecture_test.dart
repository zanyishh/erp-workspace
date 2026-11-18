import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/reports/data/erp_report_repository.dart';
import 'package:erp_client/features/reports/data/report_repository.dart';
import 'package:erp_client/features/reports/models/report_definition.dart';
import 'package:erp_client/features/reports/presentation/report_view_model.dart';
import 'package:erp_client/native_reports.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _definition() => {
  'doctype': 'Report',
  'reference': 'Sales Invoice',
  'can_export': true,
  'fields': [
    {'fieldname': 'party', 'fieldtype': 'Data', 'label': 'Party'},
    {
      'fieldname': 'company',
      'fieldtype': 'Link',
      'options': 'Company',
      'label': 'Company',
      'hidden': 1,
    },
    {
      'fieldname': 'limit',
      'fieldtype': 'Int',
      'label': 'Limit',
      'conditions': {
        'depends_on': {'op': 'field', 'name': 'party'},
      },
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
    {
      'fieldname': 'status',
      'fieldtype': 'MultiSelectList',
      'label': 'Status',
      'options': 'Open\nCompleted',
    },
  ],
  'defaults': {
    'company': 'A',
    'party_type': 'Customer',
    'people': ['Blue Mill'],
  },
};
NativeReportResult _rows(String text) => NativeReportResult.fromJson({
  'columns': [
    {'fieldname': 'party', 'label': 'Party'},
  ],
  'result': [
    {
      'party': text,
      'nested': {
        'values': [1],
      },
    },
  ],
  'report_summary': [
    {'label': 'Total', 'value': 1},
  ],
  'chart': {
    'type': 'bar',
    'data': {
      'labels': ['One'],
      'datasets': [
        {
          'values': [1],
        },
      ],
    },
  },
});

class _Repository implements ReportRepository {
  @override
  Object identity = Object();
  @override
  Object? scope = 1;
  final runs = <Map<String, dynamic>>[], queues = <Map<String, dynamic>>[];
  int definitionReads = 0, linkReads = 0;
  Completer<NativeReportResult>? pending;
  Completer<void>? pendingQueue;
  NativeReportResult output = _rows('First');
  @override
  Future<ReportDefinition> definition() async {
    definitionReads++;
    return ReportDefinition.fromJson(_definition());
  }

  @override
  Future<NativeReportResult> run(Map<String, dynamic> filters) {
    runs.add(filters);
    return pending?.future ?? Future.value(output);
  }

  @override
  Future<void> queue(Map<String, dynamic> filters) {
    queues.add(filters);
    return pendingQueue?.future ?? Future.value();
  }

  @override
  Future<List<Map<String, dynamic>>> links(
    String type,
    String query, {
    required String reference,
    required String field,
  }) async {
    linkReads++;
    return [
      {'value': 'Blue Mill'},
    ];
  }
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  Completer<Map<String, dynamic>>? pending;
  (String, String?)? definitionArguments;
  (String, Map<String, dynamic>)? runArguments, queueArguments;
  @override
  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) {
    definitionArguments = (name, company);
    return pending?.future ?? Future.value(_definition());
  }

  @override
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async {
    runArguments = (name, filters);
    return _rows('API');
  }

  @override
  Future<void> queueReport(String name, Map<String, dynamic> filters) async {
    queueArguments = (name, filters);
  }
}

void main() {
  test('report read models freeze rows, summaries and chart collections', () {
    final report = _rows('Immutable');
    expect(() => report.rows.clear(), throwsUnsupportedError);
    expect(
      () => report.rows.single['party'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => ((report.rows.single['nested'] as Map)['values'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(() => report.columns.clear(), throwsUnsupportedError);
    expect(() => report.summary.single['value'] = 2, throwsUnsupportedError);
    expect(() => report.chart!.labels.clear(), throwsUnsupportedError);
    expect(() => report.chart!.series.clear(), throwsUnsupportedError);
    expect(
      () => report.chart!.series.single.values.clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'definition snapshots defaults and gives isolated schema projections',
    () {
      final raw = _definition();
      final definition = ReportDefinition.fromJson(raw);
      (raw['defaults'] as Map)['company'] = 'B';
      expect(definition.defaults['company'], 'A');
      expect(
        () => (definition.defaults['people'] as List).clear(),
        throwsUnsupportedError,
      );
      definition.schema.fields.clear();
      expect(definition.schema.fields, isNotEmpty);
    },
  );
  test('a report definition without defaults starts with an empty draft', () {
    final raw = _definition()..remove('defaults');
    expect(ReportDefinition.fromJson(raw).defaults, isEmpty);
  });
  test('ERP adapter preserves definition and run/queue payloads', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpReportRepository(
      api: api,
      name: 'Sales Register',
      company: 'A',
    );
    await repository.definition();
    await repository.run({'party': 'Blue'});
    await repository.queue({'party': 'Green'});
    expect(api.definitionArguments, ('Sales Register', 'A'));
    expect(api.runArguments?.$1, 'Sales Register');
    expect(api.runArguments?.$2, {'party': 'Blue'});
    expect(api.queueArguments?.$1, 'Sales Register');
    expect(api.queueArguments?.$2, {'party': 'Green'});
  });
  for (final change in ['account', 'revision', 'unready']) {
    test('ERP report reads reject a changed $change', () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpReportRepository(
        api: api,
        name: 'Sales Register',
        company: 'A',
      );
      final pending = Completer<Map<String, dynamic>>();
      api.pending = pending;
      final result = repository.definition();
      final expectation = expectLater(result, throwsA(isA<ErpException>()));
      switch (change) {
        case 'account':
          api.account = 'another@example.invalid';
        case 'revision':
          api.accessRevision++;
        default:
          api.accessReady = false;
      }
      pending.complete(_definition());
      await expectation;
    });
  }
  test('draft edits do not mutate defaults and invisible values use fixed defaults', () async {
    final repository = _Repository();
    final active = ReportViewModel(repository);
    addTearDown(active.dispose);
    final definition = await active.definition;
    (active.values!['people'] as List).clear();
    active.values!['limit'] = 'invalid';
    active.values!['company'] = 'B';
    active.run();
    final applied = await active.result!;
    expect(definition.defaults['people'], ['Blue Mill']);
    expect(applied.filters['company'], 'A');
    expect(applied.filters.containsKey('limit'), isFalse);
    expect(repository.runs, hasLength(1));
  });
  test(
    'dependent choices clear in the model and static options avoid API',
    () async {
      final repository = _Repository();
      final active = ReportViewModel(repository);
      addTearDown(active.dispose);
      final definition = await active.definition;
      active.values!['party_type'] = 'Supplier';
      active.changed();
      expect(active.values!['people'], isEmpty);
      final field = definition.schema.fields.singleWhere(
        (v) => v.name == 'status',
      );
      expect(await active.links('', 'comp', field), [
        {'value': 'Completed'},
      ]);
      expect(repository.linkReads, 0);
    },
  );
  test(
    'a superseded result cannot become the next retained prepared result',
    () async {
      final repository = _Repository();
      final active = ReportViewModel(repository);
      addTearDown(active.dispose);
      await active.definition;
      final slow = Completer<NativeReportResult>();
      repository.pending = slow;
      active.run();
      final old = active.result!;
      repository.pending = null;
      repository.output = _rows('Latest');
      active.run();
      await active.result;
      slow.complete(_rows('Obsolete'));
      await old;
      repository.output = NativeReportResult.fromJson({
        'prepared_report': true,
      });
      active.run();
      final applied = await active.result!;
      expect(applied.report.rows.single['party'], 'Latest');
    },
  );
  test(
    'prepared generation snapshots requested filters despite later draft edits',
    () async {
      final repository = _Repository();
      final model = ReportViewModel(repository);
      addTearDown(model.dispose);
      await model.definition;
      model.values!['party'] = 'Blue';
      model.run();
      await model.result;
      repository.output = NativeReportResult.fromJson({
        'prepared_report': true,
      });
      model.values!['party'] = 'Green';
      model.run();
      final applied = await model.result!;
      expect(applied.filters['party'], 'Blue');
      expect(applied.preparedFilters!['party'], 'Green');
      model.values!['party'] = 'Red';
      await model.queue(applied.preparedFilters!);
      expect(repository.queues.single['party'], 'Green');
      expect((await model.result!).filters['party'], 'Blue');
    },
  );
  for (final revision in [false, true]) {
    test(
      'read refresh never releases a pending queue, revision change $revision',
      () async {
        final repository = _Repository();
        final active = ReportViewModel(repository);
        addTearDown(active.dispose);
        await active.definition;
        repository.output = NativeReportResult.fromJson({
          'prepared_report': true,
        });
        active.run();
        final applied = await active.result!;
        final pending = Completer<void>();
        repository.pendingQueue = pending;
        final writing = active.queue(applied.filters);
        expect(active.busy, isTrue);
        if (revision) repository.scope = 2;
        await active.revalidate();
        expect(active.busy, isTrue);
        active.run();
        await active.result;
        await active.queue(applied.filters);
        expect(repository.queues, hasLength(1));
        pending.complete();
        await writing;
        expect(active.busy, isFalse);
      },
    );
  }
  test(
    'exports and drafts are hidden after access or ownership changes',
    () async {
      final repository = _Repository();
      final active = ReportViewModel(repository);
      addTearDown(active.dispose);
      await active.definition;
      active.run();
      final applied = await active.result!;
      expect(active.csv(applied), contains('First'));
      repository.scope = 2;
      expect(active.values, isNull);
      expect(active.canExport(applied), isFalse);
      expect(() => active.csv(applied), throwsA(isA<ErpException>()));
      repository.identity = Object();
      expect(active.values, isNull);
    },
  );
  test(
    'unready constructor returns a failed definition future without a request',
    () async {
      final repository = _Repository()..scope = null;
      final model = ReportViewModel(repository);
      addTearDown(model.dispose);
      await expectLater(model.definition, throwsA(isA<ErpException>()));
      expect(repository.definitionReads, 0);
    },
  );
}
