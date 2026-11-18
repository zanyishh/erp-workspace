import '../models/team_snapshot.dart';

abstract class TeamRepository {
  /// Opaque account/company/access owner; null while access is quarantined.
  Object? get scope;
  Future<TeamSnapshot> load();
  Future<IssuedInvitation> invite({
    required String email,
    required String role,
  });
  Future<void> revoke(String name);
}
