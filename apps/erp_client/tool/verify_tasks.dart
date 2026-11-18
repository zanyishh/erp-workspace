// Synthetic connected contract check for the migrated task feature. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/tasks/data/erp_task_repository.dart';
import 'package:erp_client/features/tasks/models/task_page.dart';
import 'package:erp_client/features/tasks/presentation/task_planner_view_model.dart';

Future<void> main() async {
  final origin = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://127.0.0.1:8081',
  );
  if (!{'localhost', '127.0.0.1'}.contains(origin.host) ||
      origin.port != 8081 ||
      origin.scheme != 'http') {
    throw StateError(
      'Task verification requires the isolated local test site.',
    );
  }
  final username = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (username == null || password == null) {
    throw StateError(
      'Set synthetic verification credentials in the environment.',
    );
  }
  final api = ErpApi(origin);
  try {
    await api.login(username, password);
    final catalog = await api.nativeCatalog();
    if (catalog.site != 'native-test.localhost') {
      throw StateError('Refusing to write outside native-test.localhost.');
    }
    const company = 'ERP Native Verification';
    final context = await api.workspaceContext(company: company);
    if (context.company != company) {
      throw StateError('Synthetic task company is unavailable.');
    }
    final schema = await api.nativeSchema('Task');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    Future<String> create(String label, {String? start, String? end}) async {
      final document = await api.nativeDocument('Task', company: company);
      final values = document.editCopy()
        ..['company'] = company
        ..['subject'] = 'Architecture task $stamp $label'
        ..['exp_start_date'] = start
        ..['exp_end_date'] = end;
      final saved = await api.saveNative(schema, values);
      return saved.data['name'] as String;
    }

    final spanning = await create(
      'spanning',
      start: '2031-03-31',
      end: '2031-04-02',
    );
    final due = await create('due only', end: '2031-04-18');
    final outside = await create('next month', start: '2031-05-01');
    final unscheduled = await create('unscheduled');
    final repository = ErpTaskRepository(api: api, company: company);
    Future<List<TaskRecord>> readAll({String? month}) async {
      final result = <TaskRecord>[];
      var start = 0;
      for (var page = 0; page < 100; page++) {
        final loaded = await repository.load(
          month: month,
          status: 'Open',
          start: start,
        );
        result.addAll(loaded.rows);
        if (!loaded.hasMore) return result;
        if (loaded.offset <= start) {
          throw StateError('Task pagination did not advance.');
        }
        start = loaded.offset;
      }
      throw StateError('Synthetic task verification exceeded its page limit.');
    }

    final monthly = (await readAll(month: '2031-04'))
        .map((row) => row.name)
        .toSet();
    if (!monthly.containsAll({spanning, due}) ||
        monthly.contains(outside) ||
        monthly.contains(unscheduled)) {
      throw StateError(
        'Task calendar did not preserve date-overlap filtering.',
      );
    }
    final board = (await readAll()).map((row) => row.name).toSet();
    if (!board.containsAll({spanning, due, outside, unscheduled})) {
      throw StateError('Task board omitted a synthetic task.');
    }
    final model = TaskPlannerViewModel(repository, date: DateTime(2031, 4, 1));
    await model.result;
    model.selectCalendar(true);
    var page = await model.result;
    for (var pages = 1; page.hasMore && pages < 100; pages++) {
      final next = await model.loadMore(page);
      if (next.offset <= page.offset) {
        throw StateError('Task view-model pagination did not advance.');
      }
      page = next;
    }
    if (page.hasMore) {
      throw StateError('Task view-model verification exceeded its page limit.');
    }
    final days = TaskPlannerViewModel.calendarDays(
      page.rows,
      DateTime(2031, 4),
    );
    if (!days[1]!.any((row) => row.name == spanning) ||
        !days[2]!.any((row) => row.name == spanning) ||
        days[3]!.any((row) => row.name == spanning)) {
      throw StateError('Task agenda did not preserve spanning-day projection.');
    }
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'company': company,
        'createdSyntheticTasks': 4,
        'repositoryBoardAndCalendar': 'passed',
        'viewModelSpanningDays': 'passed',
      }),
    );
    await api.signOut();
  } finally {
    api.close();
  }
}
