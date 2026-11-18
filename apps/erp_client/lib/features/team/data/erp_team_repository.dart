import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/team_snapshot.dart';
import 'team_repository.dart';

class ErpTeamRepository implements TeamRepository {
  ErpTeamRepository({required this._api, required this.company});
  final ErpApi _api;
  final String company;
  @override
  Object? get scope => _api.accessReady
      ? (_api, _api.baseUri, _api.account, company, _api.accessRevision)
      : null;
  static const _changed = ErpException(
    'Access changed. Reload the team before continuing.',
    permissionDenied: true,
  );
  Future<T> _scoped<T>(Future<T> Function() request) async {
    final owner = scope;
    if (owner == null) throw _changed;
    final value = await request();
    if (owner != scope) throw _changed;
    return value;
  }

  @override
  Future<TeamSnapshot> load() async {
    final json = await _scoped(() => _api.team(company));
    try {
      return TeamSnapshot.fromJson(json);
    } on FormatException {
      throw const ErpException(
        'The team response could not be read. Refresh and try again.',
      );
    }
  }

  @override
  Future<IssuedInvitation> invite({
    required String email,
    required String role,
  }) async {
    final json = await _scoped(() => _api.inviteMember(company, email, role));
    try {
      final issued = IssuedInvitation.fromJson(json);
      if (issued.email.toLowerCase() != email.toLowerCase()) {
        throw const FormatException('Unexpected invitation recipient.');
      }
      return issued;
    } on FormatException {
      throw const ErpException(
        'The invitation code could not be read. Revoke the invitation and create a new one.',
      );
    }
  }

  @override
  Future<void> revoke(String name) =>
      _scoped(() => _api.revokeInvitation(company, name));
}
