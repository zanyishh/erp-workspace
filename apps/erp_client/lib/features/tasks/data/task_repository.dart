import '../models/task_page.dart';

abstract class TaskRepository {
  Future<TaskPage> load({String? month, String? status, int start = 0});
}
