import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/tasks/data/erp_task_repository.dart';
import 'package:erp_client/features/tasks/data/task_repository.dart';
import 'package:erp_client/features/tasks/models/task_page.dart';
import 'package:erp_client/features/tasks/presentation/task_planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String name, {String? start, String? end}) => {
  'name': name,
  'subject': 'Inspect $name',
  'status': 'Open',
  'exp_start_date': ?start,
  'exp_end_date': ?end,
};

Map<String, dynamic> _json(
  List<Map<String, dynamic>> rows, {
  bool more = false,
}) => {
  'rows': rows,
  'statuses': ['Open', 'Working'],
  'has_more': more,
};

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final calls = <(String, String?, String?, int)>[];
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> taskView(
    String company, {
    String? month,
    String? status,
    int start = 0,
  }) {
    calls.add((company, month, status, start));
    return pending.future;
  }
}

class _Tasks implements TaskRepository {
  final requests = <(String?, String?, int)>[];
  final pages = <Completer<TaskPage>>[];
  @override
  Future<TaskPage> load({String? month, String? status, int start = 0}) {
    requests.add((month, status, start));
    final page = Completer<TaskPage>();
    pages.add(page);
    return page.future;
  }
}

void main() {
  test(
    'repository preserves company/month/status/offset and immutable results',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpTaskRepository(api: api, company: 'Synthetic');
      final read = repository.load(
        month: '2031-04',
        status: 'Working',
        start: 50,
      );
      final raw = _json([_row('TASK-51')]);
      api.pending.complete(raw);
      final page = await read;
      (raw['rows'] as List).clear();
      expect(api.calls.single, ('Synthetic', '2031-04', 'Working', 50));
      expect(page.rows.single.name, 'TASK-51');
      expect(page.offset, 51);
      expect(() => page.rows.clear(), throwsUnsupportedError);
      expect(() => page.statuses.clear(), throwsUnsupportedError);
    },
  );

  test('repository rejects a response from an old access revision', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpTaskRepository(api: api, company: 'Synthetic');
    final read = repository.load();
    final result = expectLater(read, throwsA(isA<ErpException>()));
    api.accessRevision++;
    api.pending.complete(_json([_row('Protected task')]));
    await result;
  });

  test('repository rejects a response after the account changes', () async {
    final api = _Api();
    addTearDown(api.close);
    final read = ErpTaskRepository(api: api, company: 'Synthetic').load();
    final result = expectLater(read, throwsA(isA<ErpException>()));
    api.account = 'Other account';
    api.pending.complete(_json([_row('Protected task')]));
    await result;
  });

  test('repository reports a malformed page as a safe feature error', () async {
    final api = _Api();
    addTearDown(api.close);
    final read = ErpTaskRepository(api: api, company: 'Synthetic').load();
    final result = expectLater(read, throwsA(isA<ErpException>()));
    api.pending.complete({'rows': 'private malformed payload'});
    await result;
  });

  test(
    'view model keeps the current query when an older read finishes last',
    () async {
      final repository = _Tasks();
      final model = TaskPlannerViewModel(
        repository,
        date: DateTime(2031, 4, 7),
      );
      final old = model.result;
      model.selectCalendar(true);
      final current = model.result;
      repository.pages[1].complete(
        TaskPage.fromJson(_json([_row('Calendar')])),
      );
      expect((await current).rows.single.name, 'Calendar');
      repository.pages[0].complete(TaskPage.fromJson(_json([_row('Board')])));
      await old;
      expect(identical(model.result, current), isTrue);
      expect((await model.result).rows.single.name, 'Calendar');
      expect(repository.requests, [(null, null, 0), ('2031-04', null, 0)]);
    },
  );

  test(
    'view model deduplicates rows while paging with the raw offset',
    () async {
      final repository = _Tasks();
      final model = TaskPlannerViewModel(
        repository,
        date: DateTime(2031, 4, 1),
      );
      repository.pages[0].complete(
        TaskPage.fromJson(_json([_row('A')], more: true)),
      );
      final first = await model.result;
      model.loadMore(first);
      repository.pages[1].complete(
        TaskPage.fromJson(_json([_row('A'), _row('B')], more: true), start: 1),
      );
      final merged = await model.result;
      expect(merged.rows.map((r) => r.name), ['A', 'B']);
      expect(merged.offset, 3);
      model.loadMore(merged);
      repository.pages[2].complete(
        TaskPage.fromJson(_json([_row('C')]), start: 3),
      );
      await model.result;
      expect(repository.requests.map((r) => r.$3), [0, 1, 3]);
    },
  );

  test('calendar projection includes spanning and due-only tasks, omits undated tasks', () {
    final rows = TaskPage.fromJson(
      _json([
        _row('Span', start: '2031-03-31 10:00:00', end: '2031-04-02 11:00:00'),
        _row('Due', end: '2031-04-18'),
        _row('Undated'),
      ]),
    ).rows;
    final days = TaskPlannerViewModel.calendarDays(rows, DateTime(2031, 4));
    expect(days[1]!.map((r) => r.name), ['Span']);
    expect(days[2]!.map((r) => r.name), ['Span']);
    expect(days[3], isEmpty);
    expect(days[18]!.map((r) => r.name), ['Due']);
    expect(
      days.values.expand((r) => r).any((r) => r.name == 'Undated'),
      isFalse,
    );
  });
}
