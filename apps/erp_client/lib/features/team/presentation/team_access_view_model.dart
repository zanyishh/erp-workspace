import '../../../core/models/erp_exception.dart';
import '../../../core/models/email_address.dart';
import '../data/team_repository.dart';
import '../models/team_snapshot.dart';

class TeamAccessViewModel {
  TeamAccessViewModel(this._repository) {
    refresh();
  }
  final TeamRepository _repository;
  late Future<TeamSnapshot> result;
  TeamSnapshot? _snapshot;
  Object? _loadedScope, _issuedScope, _busyToken;
  IssuedInvitation? _issued;
  String? _error;
  String? role;
  int _generation = 0;
  bool _disposed = false;
  String? get error => _error;
  bool get busy => !_disposed && _busyToken != null;
  IssuedInvitation? get issued =>
      !_disposed && _issuedScope != null && _issuedScope == _repository.scope
      ? _issued
      : null;
  bool isCurrentInvitation(IssuedInvitation value) => identical(issued, value);
  bool accepts(TeamSnapshot? value) =>
      !_disposed &&
      _loadedScope != null &&
      _loadedScope == _repository.scope &&
      identical(_snapshot, value);
  bool _current(int generation, Object? scope) =>
      !_disposed &&
      generation == _generation &&
      scope != null &&
      scope == _repository.scope;
  static const _changed = ErpException(
    'Access changed. Reload the team before continuing.',
    permissionDenied: true,
  );
  static String? validateEmail(String? value) =>
      isEmailAddress(value ?? '') ? null : 'Enter a valid email address.';
  String? validateRole(String? value) =>
      _snapshot?.roles.containsKey(value) == true
      ? null
      : 'Choose a role for this invitation.';
  String roleName(String value) =>
      _snapshot?.roles[value] ?? (value == 'owner' ? 'Owner' : value);

  Future<TeamSnapshot> refresh({bool clearIssued = false}) {
    final generation = ++_generation, scope = _repository.scope;
    _error = null;
    if (clearIssued || _issuedScope != scope) _issued = null;
    if (_loadedScope != scope) {
      _snapshot = null;
      _loadedScope = null;
    }
    result = _load(generation, scope);
    // The view attaches on its next frame; retain the error for that consumer.
    result.ignore();
    return result;
  }

  Future<TeamSnapshot> _load(int generation, Object? scope) async {
    final data = await _repository.load();
    if (!_current(generation, scope)) throw _changed;
    _snapshot = data;
    _loadedScope = scope;
    return data;
  }

  Future<void> revalidate() async {
    await refresh(clearIssued: true);
  }

  void inviteAnother() {
    _issued = null;
    role = null;
  }

  void reportShareFailure(IssuedInvitation value) {
    if (isCurrentInvitation(value)) {
      _error = 'Select the invitation code and copy it to share it with your teammate.';
    }
  }

  Future<bool> invite(String input) async {
    if (validateEmail(input) != null || validateRole(role) != null) {
      return false;
    }
    return _command(() async {
      final value = await _repository.invite(email: input.trim(), role: role!);
      return value;
    });
  }

  Future<bool> revoke(TeamInvitation invitation) {
    if (_snapshot?.invitations.any(
          (row) => row.name == invitation.name && row.email == invitation.email,
        ) !=
        true) {
      return Future.value(false);
    }
    return _command(
      () async {
        await _repository.revoke(invitation.name);
        return null;
      },
      inviting: false,
      revokedEmail: invitation.email,
    );
  }

  Future<bool> _command(
    Future<IssuedInvitation?> Function() command, {
    bool inviting = true,
    String? revokedEmail,
  }) async {
    if (_disposed || busy) return false;
    final scope = _repository.scope, generation = _generation;
    if (scope == null || scope != _loadedScope) {
      _issued = null;
      _error = _changed.toString();
      return false;
    }
    final token = Object();
    _busyToken = token;
    _error = null;
    if (inviting) _issued = null;
    try {
      final value = await command();
      if (!_current(generation, scope)) return false;
      if (inviting) {
        _issued = value;
        _issuedScope = scope;
      } else if (_issued?.email == revokedEmail) {
        _issued = null;
      }
      refresh();
      return true;
    } catch (error) {
      if (_current(generation, scope)) _error = error.toString();
      return false;
    } finally {
      if (identical(_busyToken, token)) _busyToken = null;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _issued = null;
    _snapshot = null;
    _busyToken = null;
  }
}
