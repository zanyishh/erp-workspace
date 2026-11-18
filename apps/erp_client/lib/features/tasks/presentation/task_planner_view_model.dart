import '../data/task_repository.dart';
import '../models/task_page.dart';

class TaskPlannerViewModel {
  TaskPlannerViewModel(
    this._repository, {
    DateTime? date,
    bool calendar = false,
    String? status,
  }) : _date = _dateOnly(date ?? DateTime.now()) {
    _calendar = calendar;
    _status = status;
    _result = _read();
  }
  final TaskRepository _repository;
  bool _calendar = false;
  DateTime _date;
  String? _status;
  late Future<TaskPage> _result;
  bool get calendar => _calendar;
  DateTime get date => _date;
  String? get status => _status;
  Future<TaskPage> get result => _result;

  String? get _month => _calendar
      ? '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}'
      : null;
  Future<TaskPage> _read() => _repository.load(month: _month, status: _status);
  Future<TaskPage> reload() => _result = _read();
  void selectCalendar(bool value) {
    _calendar = value;
    reload();
  }

  void selectDate(DateTime value) {
    _date = _dateOnly(value);
    reload();
  }

  void shiftMonth(int delta) {
    _date = DateTime(_date.year, _date.month + delta);
    reload();
  }

  void selectStatus(String? value) {
    _status = value == '' ? null : value;
    reload();
  }

  Future<TaskPage> loadMore(TaskPage previous) =>
      _result = _append(previous, month: _month, status: _status);
  Future<TaskPage> _append(
    TaskPage previous, {
    String? month,
    String? status,
  }) async {
    final next = await _repository.load(
      month: month,
      status: status,
      start: previous.offset,
    );
    final seen = {for (final row in previous.rows) row.name};
    return TaskPage(
      rows: [
        ...previous.rows,
        for (final row in next.rows)
          if (seen.add(row.name)) row,
      ],
      statuses: next.statuses,
      hasMore: next.hasMore,
      offset: next.offset,
    );
  }

  List<TaskGroup> boardGroups(TaskPage page) {
    final groups = {for (final status in page.statuses) status: <TaskRecord>[]};
    for (final row in page.rows) {
      (groups[row.status] ??= []).add(row);
    }
    return List.unmodifiable([
      for (final entry in groups.entries)
        if (_status == null ? entry.value.isNotEmpty : entry.key == _status)
          TaskGroup(entry.key, entry.value),
    ]);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static Map<int, List<TaskRecord>> calendarDays(
    Iterable<TaskRecord> rows,
    DateTime month,
  ) {
    final count = DateTime(month.year, month.month + 1, 0).day;
    final range = {for (var day = 1; day <= count; day++) day: <TaskRecord>[]};
    for (final row in rows) {
      if (row.start == null && row.end == null) continue;
      final start = _dateOnly((row.start ?? row.end)!);
      final end = _dateOnly((row.end ?? row.start)!);
      for (var day = 1; day <= count; day++) {
        final date = DateTime(month.year, month.month, day);
        if (!date.isBefore(start) && !date.isAfter(end)) range[day]!.add(row);
      }
    }
    return Map.unmodifiable({
      for (final entry in range.entries)
        entry.key: List<TaskRecord>.unmodifiable(entry.value),
    });
  }
}
