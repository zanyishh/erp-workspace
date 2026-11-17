import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/task_page.dart';
import 'task_repository.dart';

class ErpTaskRepository implements TaskRepository {
  ErpTaskRepository({required this._api, required this.company});
  final ErpApi _api;
  final String company;

  @override
  Future<TaskPage> load({String? month, String? status, int start = 0}) async {
    final account = _api.account, revision = _api.accessRevision;
    void checkAccess() {
      if (!_api.accessReady ||
          account != _api.account ||
          revision != _api.accessRevision) {
        throw const ErpException(
          'Access changed. Reload this view before continuing.',
        );
      }
    }

    checkAccess();
    final response = await _api.taskView(
      company,
      month: month,
      status: status,
      start: start,
    );
    checkAccess();
    try {
      return TaskPage.fromJson(response, start: start);
    } on FormatException {
      throw const ErpException(
        'ERPNext returned an invalid task list. Refresh and try again.',
      );
    }
  }
}
