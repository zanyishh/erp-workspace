class TaskRecord {
  const TaskRecord({
    required this.name,
    required this.title,
    required this.status,
    this.project,
    this.start,
    this.end,
  });
  factory TaskRecord.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Invalid task identity.');
    }
    final project = json['project']?.toString();
    return TaskRecord(
      name: name,
      title: json['subject']?.toString() ?? name,
      status: json['status']?.toString() ?? 'Unspecified',
      project: project == '' ? null : project,
      start: DateTime.tryParse(json['exp_start_date']?.toString() ?? ''),
      end: DateTime.tryParse(json['exp_end_date']?.toString() ?? ''),
    );
  }
  final String name, title, status;
  final String? project;
  final DateTime? start, end;
  String get subtitle => [?project, name].join(' · ');
}

class TaskPage {
  TaskPage({
    required Iterable<TaskRecord> rows,
    required Iterable<String> statuses,
    required this.hasMore,
    required this.offset,
  }) : rows = List.unmodifiable(rows),
       statuses = List.unmodifiable(statuses);

  factory TaskPage.fromJson(Map<String, dynamic> json, {int start = 0}) {
    final rows = json['rows'], statuses = json['statuses'];
    if (rows is! List ||
        statuses is! List ||
        statuses.any((s) => s is! String) ||
        json['has_more'] is! bool) {
      throw const FormatException('Invalid task page.');
    }
    return TaskPage(
      rows: rows.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid task row.');
        }
        return TaskRecord.fromJson(row);
      }),
      statuses: List<String>.from(statuses),
      hasMore: json['has_more'] as bool,
      offset: start + rows.length,
    );
  }
  final List<TaskRecord> rows;
  final List<String> statuses;
  final bool hasMore;
  final int offset;
}

class TaskGroup {
  TaskGroup(this.status, Iterable<TaskRecord> rows)
    : rows = List.unmodifiable(rows);
  final String status;
  final List<TaskRecord> rows;
}
