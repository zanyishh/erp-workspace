import 'package:flutter/material.dart';

import '../../../core/ui/widgets.dart';
import '../models/task_page.dart';
import 'task_planner_view_model.dart';

class TaskPlannerView extends StatefulWidget {
  const TaskPlannerView({
    super.key,
    required this.model,
    required this.open,
    required this.protect,
  });
  final TaskPlannerViewModel model;
  final Future<void> Function(String name) open;
  final Widget Function(Widget child, Future<void> Function() reload) protect;
  @override
  State<TaskPlannerView> createState() => _TaskPlannerViewState();
}

class _TaskPlannerViewState extends State<TaskPlannerView> {
  void _change(VoidCallback command) => setState(() {
    command();
  });
  Future<void> _reload() async {
    final next = widget.model.reload();
    setState(() {});
    await next;
  }

  Future<void> _open(String name) async {
    final model = widget.model;
    await widget.open(name);
    if (mounted && identical(model, widget.model)) _change(model.reload);
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: widget.model.date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (selected != null && mounted) {
      _change(() => widget.model.selectDate(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return widget.protect(
      Scaffold(
        appBar: AppBar(
          title: const Text('Task planner'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh tasks',
              onPressed: () => _change(model.reload),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Board'),
                          icon: Icon(Icons.view_kanban_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Calendar'),
                          icon: Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                      selected: {model.calendar},
                      onSelectionChanged: (s) =>
                          _change(() => model.selectCalendar(s.single)),
                    ),
                    if (model.calendar)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Previous month',
                            onPressed: () =>
                                _change(() => model.shiftMonth(-1)),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          TextButton(
                            onPressed: _selectDate,
                            child: Text(
                              MaterialLocalizations.of(context)
                                  .formatMonthYear(model.date),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next month',
                            onPressed: () => _change(() => model.shiftMonth(1)),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<TaskPage>(
                    future: model.result,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return MessagePanel(
                          title: 'Could not load tasks',
                          message: snapshot.error.toString(),
                          action: () => _change(model.reload),
                        );
                      }
                      if (snapshot.connectionState != ConnectionState.done ||
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!;
                      final rows = data.rows;
                      final statuses = data.statuses;
                      final more = data.hasMore;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<String>(
                              tooltip: 'Filter by task status',
                              initialValue: model.status ?? '',
                              onSelected: (s) =>
                                  _change(() => model.selectStatus(s)),
                              itemBuilder: (_) => [
                                for (final s in ['', ...statuses])
                                  PopupMenuItem(
                                    value: s,
                                    child: Text(s.isEmpty ? 'All statuses' : s),
                                  ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.filter_list, size: 18),
                                    const SizedBox(width: 6),
                                    Text(model.status ?? 'All statuses'),
                                    const Icon(Icons.arrow_drop_down),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (more)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.more_horiz),
                                onPressed: () =>
                                    _change(() => model.loadMore(data)),
                                label: Text(
                                  'Load more tasks (${rows.length} shown)',
                                ),
                              ),
                            ),
                          Expanded(
                            child: rows.isEmpty
                                ? Center(
                                    child: Text(
                                      model.calendar
                                          ? 'No scheduled tasks this month.'
                                          : 'No tasks match this view.',
                                    ),
                                  )
                                : model.calendar
                                ? _CalendarAgenda(
                                    date: model.date,
                                    rows: rows,
                                    open: _open,
                                  )
                                : _TaskBoard(
                                    groups: model.boardGroups(data),
                                    open: _open,
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _reload,
    );
  }
}

class _TaskBoard extends StatelessWidget {
  const _TaskBoard({required this.groups, required this.open});
  final List<TaskGroup> groups;
  final ValueChanged<String> open;
  @override
  Widget build(BuildContext context) {
    final visible = groups;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.clamp(180.0, 286.0);
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (c, i) => SizedBox(
            width: width,
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      visible[i].status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible[i].rows.length,
                      itemBuilder: (_, j) =>
                          _taskTile(visible[i].rows[j], open),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _taskTile(TaskRecord row, ValueChanged<String> open) => ListTile(
  title: Text(row.title),
  subtitle: Text(row.subtitle),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => open(row.name),
);

class _CalendarAgenda extends StatefulWidget {
  const _CalendarAgenda({
    required this.date,
    required this.rows,
    required this.open,
  });
  final DateTime date;
  final List<TaskRecord> rows;
  final ValueChanged<String> open;
  @override
  State<_CalendarAgenda> createState() => _CalendarAgendaState();
}

class _CalendarAgendaState extends State<_CalendarAgenda> {
  late DateTime _day = widget.date;
  @override
  void didUpdateWidget(_CalendarAgenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.date != oldWidget.date) _day = widget.date;
  }

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final first = DateTime(_day.year, _day.month);
    final days = DateUtils.getDaysInMonth(_day.year, _day.month);
    final offset = DateUtils.firstDayOffset(_day.year, _day.month, locale);
    final range = TaskPlannerViewModel.calendarDays(widget.rows, _day);
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Center(
                          child: Text(
                            locale.narrowWeekdays[(locale.firstDayOfWeekIndex +
                                    i) %
                                7],
                          ),
                        ),
                      ),
                  ],
                ),
                for (var week = 0; week < (days + offset) / 7; week++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final n = week * 7 + col - offset + 1;
                              if (n < 1 || n > days) {
                                return const SizedBox(height: 44);
                              }
                              final date = DateTime(first.year, first.month, n);
                              final selected = n == _day.day;
                              final count = range[n]!.length;
                              return Semantics(
                                button: true,
                                selected: selected,
                                label:
                                    '${locale.formatFullDate(date)}, $count tasks',
                                excludeSemantics: true,
                                onTap: () => setState(() => _day = date),
                                child: InkWell(
                                  onTap: () => setState(() => _day = date),
                                  borderRadius: BorderRadius.circular(7),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 44,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer
                                          : null,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('$n'),
                                        SizedBox(
                                          height: 5,
                                          child: count > 0
                                              ? const Icon(
                                                  Icons.circle,
                                                  size: 5,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            locale.formatFullDate(_day),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (range[_day.day]!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No scheduled tasks on this day.'),
          ),
        for (final row in range[_day.day]!) _taskTile(row, widget.open),
      ],
    );
  }
}
