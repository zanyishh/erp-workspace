import 'package:flutter/material.dart';

import '../../document_editor.dart';
import '../../erp_api.dart';
import '../../features/tasks/data/erp_task_repository.dart';
import '../../features/tasks/presentation/task_planner_view.dart';
import '../../features/tasks/presentation/task_planner_view_model.dart';
import '../../ui/access_gate.dart';

/// Compatibility composition for existing routes; the feature uses repository DI.
class TaskPlanner extends StatefulWidget {
  const TaskPlanner({super.key, required this.api, required this.company});
  final ErpApi api;
  final String company;
  @override
  State<TaskPlanner> createState() => _TaskPlannerState();
}

class _TaskPlannerState extends State<TaskPlanner> {
  late TaskPlannerViewModel _model = _createModel();
  TaskPlannerViewModel _createModel([TaskPlannerViewModel? previous]) =>
      TaskPlannerViewModel(
        ErpTaskRepository(api: widget.api, company: widget.company),
        date: previous?.date,
        calendar: previous?.calendar ?? false,
        status: previous?.status,
      );
  @override
  void didUpdateWidget(covariant TaskPlanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.company != widget.company) {
      _model = _createModel(_model);
    }
  }

  Future<void> _open(String name) async {
    final api = widget.api, company = widget.company;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: 'Task',
          name: name,
          company: company,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TaskPlannerView(
    model: _model,
    open: _open,
    protect: (child, reload) => AccessGate(
      key: ValueKey(widget.company),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}
