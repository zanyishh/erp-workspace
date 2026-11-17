import '../../../core/models/erp_exception.dart';
import '../../../core/models/workspace_context.dart';
import '../../../core/services/local_workspace.dart';
import '../../../erp_api.dart' show ErpApi;
import 'workspace_repository.dart';

class ErpWorkspaceRepository implements WorkspaceRepository {
  ErpWorkspaceRepository(this._api, {this._local, this._requestedCompany});
  final ErpApi _api;
  final LocalWorkspace? _local;
  final String? _requestedCompany;
  Object? _localValidatedFor;
  @override
  Object get identity => (_api, _api.baseUri, _api.account);
  @override
  Object? get accessScope =>
      _api.accessReady ? (identity, _api.accessRevision) : null;
  Future<WorkspaceContext> _scoped(
    Future<WorkspaceContext> Function() read,
    String? company,
  ) async {
    final owner = identity;
    final value = await read();
    if (owner != identity) {
      throw const ErpException(
        'The workspace account changed. Reconnect and try again.',
        permissionDenied: true,
      );
    }
    if (company != null && value.company != company) {
      throw const ErpException(
        'This company is unavailable. Refresh workspace access.',
      );
    }
    final local = _local;
    // The launch profile pins the initial connection. Later permission refreshes
    // may choose another company authorized by the same server account.
    if (local != null &&
        _localValidatedFor != owner &&
        (local.api != _api ||
            value.company != local.company ||
            _requestedCompany != null && local.company != _requestedCompany ||
            !value.companies.any((row) => row['name'] == local.company) ||
            local.workspaceId == null &&
                (value.companies.length != 1 || !value.canManageTeam))) {
      throw const ErpException(
        'This local company is unavailable. Run the ERP Workspace launcher to reconnect.',
      );
    }
    if (local != null) {
      _localValidatedFor = owner;
    }
    return value;
  }

  @override
  Future<WorkspaceContext> load({String? company}) =>
      _scoped(() => _api.workspaceContext(company: company), company);
  @override
  Future<WorkspaceContext> current(String? company) async {
    final owner = identity;
    try {
      return await load(company: company);
    } on ErpException catch (error) {
      if (!error.permissionDenied || owner != identity) rethrow;
      return load();
    }
  }

  @override
  Future<WorkspaceContext> select(String company) =>
      _scoped(() => _api.selectCompany(company), company);
}
