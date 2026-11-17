import '../../../core/models/workspace_context.dart';

abstract class WorkspaceRepository {
  Object get identity;
  Object? get accessScope;
  Future<WorkspaceContext> load({String? company});
  Future<WorkspaceContext> current(String? company);
  Future<WorkspaceContext> select(String company);
}
