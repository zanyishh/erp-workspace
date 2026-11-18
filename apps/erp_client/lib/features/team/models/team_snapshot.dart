String _required(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid team response.');
  }
  return value;
}

String? _optional(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) {
    throw const FormatException('Invalid team response.');
  }
  return value as String?;
}

class TeamMember {
  const TeamMember({required this.email, required this.role, this.fullName});
  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    email: _required(json, 'email'),
    role: _required(json, 'role'),
    fullName: _optional(json, 'full_name'),
  );
  final String email, role;
  final String? fullName;
}

class TeamInvitation {
  const TeamInvitation({
    required this.name,
    required this.email,
    required this.role,
    required this.expiresAt,
  });
  factory TeamInvitation.fromJson(Map<String, dynamic> json) => TeamInvitation(
    name: _required(json, 'name'),
    email: _required(json, 'email'),
    role: _required(json, 'role'),
    expiresAt: _required(json, 'expires_at'),
  );
  final String name, email, role, expiresAt;
}

class IssuedInvitation {
  const IssuedInvitation({
    required this.email,
    required this.token,
    this.role,
    this.expiresAt,
  });
  factory IssuedInvitation.fromJson(Map<String, dynamic> json) =>
      IssuedInvitation(
        email: _required(json, 'email'),
        token: _required(json, 'token'),
        role: _optional(json, 'role'),
        expiresAt: _optional(json, 'expires_at'),
      );
  final String email, token;
  final String? role, expiresAt;
}

class TeamSnapshot {
  TeamSnapshot({
    required Map<String, String> roles,
    required Iterable<TeamMember> members,
    required Iterable<TeamInvitation> invitations,
  }) : roles = Map.unmodifiable(roles),
       members = List.unmodifiable(members),
       invitations = List.unmodifiable(invitations);
  factory TeamSnapshot.fromJson(Map<String, dynamic> json) {
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
      final values = json[key];
      if (values is! List) {
        throw const FormatException('Invalid team response.');
      }
      return values.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid team response.');
        }
        return parse(value);
      }).toList();
    }

    final roles = rows(
      'roles',
      (row) => MapEntry(_required(row, 'key'), _required(row, 'label')),
    );
    return TeamSnapshot(
      roles: Map.fromEntries(roles),
      members: rows('members', TeamMember.fromJson),
      invitations: rows('invitations', TeamInvitation.fromJson),
    );
  }
  final Map<String, String> roles;
  final List<TeamMember> members;
  final List<TeamInvitation> invitations;
}
