import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/features/overview/data/overview_repository.dart';
import 'package:erp_client/features/overview/data/erp_overview_repository.dart';
import 'package:erp_client/features/overview/data/module_record_repository.dart';
import 'package:erp_client/features/overview/presentation/overview_view_model.dart';
import 'package:erp_client/features/overview/presentation/module_browser_view_model.dart';
import 'package:erp_client/features/overview/presentation/sales_chart_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

ErpSnapshot _snapshot({
  String company = 'A',
  double? billed = 10,
  List<SalesDay>? sales,
  Map<ErpModule, int?>? counts,
}) => ErpSnapshot(
  company: company,
  currency: 'INR',
  billed: billed,
  counts: counts ?? {ErpModule.stock: 5, ErpModule.accounts: null},
  sales: sales ?? [SalesDay(DateTime(2026, 2, 1), 10)],
);

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  Future<ErpSnapshot> next = Future.value(_snapshot());
  final snapshots = <(ReportingPeriod, String?)>[];
  final recordReads =
      <(ErpModule, String, ReportingPeriod, String, int, bool)>[];
  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) {
    snapshots.add((period, selectedCompany));
    return next;
  }

  @override
  Future<List<ErpRecord>> records(
    ErpModule module, {
    required String company,
    ReportingPeriod period = ReportingPeriod.month,
    DateTime? now,
    String query = '',
    int start = 0,
    int limit = 50,
    bool unpaidOnly = false,
  }) async {
    recordReads.add((module, company, period, query, start, unpaidOnly));
    return [
      ErpRecord({'name': 'ROW-1'}, module),
    ];
  }
}

class _Repository implements OverviewRepository {
  final reads = <(ReportingPeriod, Completer<ErpSnapshot>)>[];
  final recordReads = <(ErpModule, ReportingPeriod, String, int, bool)>[];
  @override
  Object get scope => this;
  @override
  Future<ErpSnapshot> snapshot(ReportingPeriod period) {
    final result = Completer<ErpSnapshot>();
    reads.add((period, result));
    return result.future;
  }

  @override
  Future<List<ErpRecord>> records(
    ErpModule module,
    ReportingPeriod period, {
    String query = '',
    int start = 0,
    bool unpaidOnly = false,
  }) async {
    recordReads.add((module, period, query, start, unpaidOnly));
    return [];
  }
}

class _Records implements ModuleRecordRepository {
  final reads = <(String, int)>[];
  @override
  Future<List<ErpRecord>> load(String query, int start) async {
    reads.add((query, start));
    return [];
  }
}

void main() {
  test(
    'repository preserves company, period, unpaid filter and page offset',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpOverviewRepository(api: api, company: 'A');
      await repository.snapshot(ReportingPeriod.year);
      await repository.records(
        ErpModule.accounts,
        ReportingPeriod.days30,
        query: 'invoice',
        start: 50,
        unpaidOnly: true,
      );
      expect(api.snapshots, [(ReportingPeriod.year, 'A')]);
      expect(api.recordReads, [
        (ErpModule.accounts, 'A', ReportingPeriod.days30, 'invoice', 50, true),
      ]);
    },
  );
  test('repository snapshots freeze read collections and preserve unavailable totals', () async {
    final counts = <ErpModule, int?>{
      ErpModule.stock: 5,
      ErpModule.accounts: null,
    };
    final sales = <SalesDay>[SalesDay(DateTime(2026, 2, 1), 10)];
    final api = _Api()
      ..next = Future.value(
        _snapshot(billed: null, sales: sales, counts: counts),
      );
    addTearDown(api.close);
    final repository = ErpOverviewRepository(api: api, company: 'A');
    final value = await repository.snapshot(ReportingPeriod.month);
    counts[ErpModule.stock] = 100;
    sales.clear();
    expect(value.count(ErpModule.stock), 5);
    expect(value.sales, hasLength(1));
    expect(value.billed, isNull);
    expect(value.count(ErpModule.accounts), isNull);
    expect(() => value.counts.clear(), throwsUnsupportedError);
    expect(() => value.sales.clear(), throwsUnsupportedError);
    expect(() => value.activity.clear(), throwsUnsupportedError);
    final rows = await repository.records(
      ErpModule.stock,
      ReportingPeriod.month,
    );
    expect(() => rows.clear(), throwsUnsupportedError);
  });
  for (final change in ['account', 'revision', 'readiness']) {
    test(
      'repository rejects a delayed snapshot after changed $change',
      () async {
        final pending = Completer<ErpSnapshot>();
        final api = _Api()..next = pending.future;
        addTearDown(api.close);
        final repository = ErpOverviewRepository(api: api, company: 'A');
        final reading = repository.snapshot(ReportingPeriod.month);
        final rejected = expectLater(
          reading,
          throwsA(
            isA<ErpException>().having(
              (e) => e.permissionDenied,
              'permission denied',
              isTrue,
            ),
          ),
        );
        if (change == 'account') {
          api.account = 'replacement@example.invalid';
        }
        if (change == 'revision') {
          api.accessRevision++;
        }
        if (change == 'readiness') {
          api.accessReady = false;
        }
        pending.complete(_snapshot());
        await rejected;
      },
    );
  }
  test(
    'repository rejects another company and preserves original failures',
    () async {
      final api = _Api()..next = Future.value(_snapshot(company: 'B'));
      addTearDown(api.close);
      final repository = ErpOverviewRepository(api: api, company: 'A');
      await expectLater(
        repository.snapshot(ReportingPeriod.month),
        throwsA(isA<ErpException>()),
      );
      const error = ErpException('Sign in again', sessionExpired: true);
      api.next = Future.error(error);
      await expectLater(
        repository.snapshot(ReportingPeriod.month),
        throwsA(same(error)),
      );
    },
  );
  test('overview keeps the newest future and its injected period', () async {
    final repository = _Repository();
    final model = OverviewViewModel(repository, period: ReportingPeriod.year);
    final old = model.result;
    final newest = model.reload();
    repository.reads[1].$2.complete(_snapshot(company: 'newest'));
    await newest;
    repository.reads[0].$2.complete(_snapshot(company: 'old'));
    await old;
    expect(model.result, same(newest));
    expect((await model.result).company, 'newest');
    expect(
      repository.reads.map((r) => r.$1),
      everyElement(ReportingPeriod.year),
    );
    await model.records(
      ErpModule.accounts,
      query: 'due',
      start: 100,
      unpaidOnly: true,
    );
    expect(repository.recordReads, [
      (ErpModule.accounts, ReportingPeriod.year, 'due', 100, true),
    ]);
    model.dispose();
    expect(() => model.reload(), throwsStateError);
    expect(repository.reads, hasLength(2));
  });
  test(
    'module model resets pages and opened record only when the query resets',
    () async {
      final repository = _Records();
      final model = ModuleBrowserViewModel(
        repository,
        company: 'A',
        currency: 'INR',
        module: ErpModule.stock,
      );
      await model.result;
      await model.nextPage();
      model.opened('ROW-1');
      await model.reload(query: '');
      expect(model.start, 50);
      expect(model.openedRecord, 'ROW-1');
      await model.reload(query: '  cotton  ');
      expect(model.start, 0);
      expect(model.query, 'cotton');
      expect(model.openedRecord, isNull);
      await model.nextPage();
      await model.previousPage();
      expect(repository.reads, [
        ('', 0),
        ('', 50),
        ('', 50),
        ('cotton', 0),
        ('cotton', 50),
        ('cotton', 0),
      ]);
      model.dispose();
      expect(() => model.reload(query: ''), throwsStateError);
    },
  );
  test('callback record adapter takes an immutable read copy', () async {
    final rows = [
      ErpRecord({'name': 'ROW-1'}, ErpModule.stock),
    ];
    final repository = CallbackModuleRecordRepository(
      (query, start) async => rows,
    );
    final loaded = await repository.load('', 0);
    rows.clear();
    expect(loaded, hasLength(1));
    expect(() => loaded.clear(), throwsUnsupportedError);
  });
  test('chart projection aggregates repeated dates, missing days and signed credit notes', () {
    final model = SalesChartViewModel(
      _snapshot(
        sales: [
          SalesDay(DateTime(2026, 2, 1), 20),
          SalesDay(DateTime(2026, 2, 1, 12), -5),
          SalesDay(DateTime(2026, 2, 3), -2),
        ],
      ),
      range: DateRange(DateTime(2026, 2), DateTime(2026, 2, 5)),
    );
    expect(model.buckets.map((r) => r.amount), [15, 0, -2, 0]);
    expect(model.selected, 2);
    expect(model.monthly, isFalse);
    expect(model.select(-1), isFalse);
    expect(model.select(0), isTrue);
    expect(model.select(0), isFalse);
    expect(() => model.buckets.clear(), throwsUnsupportedError);
  });
  test(
    'chart retains an inspected date only within the same company and period',
    () {
      final range = DateRange(DateTime(2026, 2), DateTime(2026, 2, 5));
      final sample = _snapshot(
        sales: [
          SalesDay(DateTime(2026, 2, 1), 10),
          SalesDay(DateTime(2026, 2, 3), 20),
        ],
      );
      final model = SalesChartViewModel(sample, range: range);
      model.select(1);
      model.update(_snapshot(sales: sample.sales), range: range);
      expect(model.buckets[model.selected].day, DateTime.utc(2026, 2, 2));
      model.update(
        _snapshot(company: 'B', sales: sample.sales),
        range: range,
      );
      expect(model.buckets[model.selected].day, DateTime.utc(2026, 2, 3));
      model.update(
        _snapshot(company: 'B', billed: null, sales: sample.sales),
        range: range,
      );
      expect(model.buckets, isEmpty);
    },
  );
  test(
    'chart monthly threshold and end-exclusive projection remain unchanged',
    () {
      final sample = _snapshot(
        sales: [
          SalesDay(DateTime(2026, 1, 1), 10),
          SalesDay(DateTime(2026, 2, 1), -2),
          SalesDay(DateTime(2026, 3, 1), 999),
        ],
      );
      final model = SalesChartViewModel(
        sample,
        range: DateRange(DateTime(2026), DateTime(2026, 3, 5)),
      );
      expect(model.monthly, isTrue);
      expect(model.buckets.map((d) => d.amount), [10, -2, 999]);
      model.update(
        sample,
        range: DateRange(DateTime(2026), DateTime(2026, 3, 1)),
      );
      expect(model.monthly, isFalse);
      expect(model.buckets, hasLength(59));
      expect(model.buckets.fold<double>(0, (v, d) => v + d.amount), 8);
    },
  );
}
