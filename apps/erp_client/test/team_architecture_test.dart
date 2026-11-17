import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/team/data/erp_team_repository.dart';
import 'package:erp_client/features/team/data/team_repository.dart';
import 'package:erp_client/features/team/models/team_snapshot.dart';
import 'package:erp_client/features/team/presentation/team_access_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _team() => {
  'roles': [
    {'key': 'sales', 'label': 'Sales'},
  ],
  'members': [
    {'email': 'owner@example.invalid', 'role': 'owner'},
  ],
  'invitations': [
    {
      'name': 'invite-1',
      'email': 'staff@example.invalid',
      'role': 'sales',
      'expires_at': '2031-04-18',
    },
  ],
};
IssuedInvitation _issued() => IssuedInvitation.fromJson({
  'token': 'synthetic-secret',
  'email': 'staff@example.invalid',
});

class _Repository implements TeamRepository {
  Object? token = Object();
  @override
  Object? get scope => token;
  final invitations = <(String, String)>[];
  final revocations = <String>[];
  final pending = Completer<IssuedInvitation>();
  Object? revokeError;
  Object? loadError;
  Completer<void>? pendingRevoke;
  @override
  Future<TeamSnapshot> load() async {
    if (loadError case final error?) throw error;
    return TeamSnapshot.fromJson(_team());
  }

  @override
  Future<IssuedInvitation> invite({
    required String email,
    required String role,
  }) {
    invitations.add((email, role));
    return pending.future;
  }

  @override
  Future<void> revoke(String name) async {
    revocations.add(name);
    if (revokeError case final error?) throw error;
    await pendingRevoke?.future;
  }
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final loaded = Completer<Map<String, dynamic>>();
  final calls = <String>[];
  Map<String, dynamic> response = {
    'token': 'synthetic-secret',
    'email': 'staff@example.invalid',
  };
  @override
  Future<Map<String, dynamic>> team(String company) {
    calls.add(company);
    return loaded.future;
  }

  @override
  Future<Map<String, dynamic>> inviteMember(
    String company,
    String email,
    String role,
  ) async => response;
}

void main() {
  test(
    'team reads are immutable and preserve owner and staff role labels',
    () async {
      final repository = _Repository();
      final model = TeamAccessViewModel(repository);
      final data = await model.result;
      expect(model.roleName('owner'), 'Owner');
      expect(model.roleName('sales'), 'Sales');
      expect(() => data.roles.clear(), throwsUnsupportedError);
      expect(() => data.members.clear(), throwsUnsupportedError);
      expect(() => data.invitations.clear(), throwsUnsupportedError);
    },
  );
  test('invitation validation and busy state prevent invalid or duplicate commands', () async {
    final repository = _Repository();
    final model = TeamAccessViewModel(repository);
    await model.result;
    model.role = 'sales';
    expect(await model.invite('invalid'), isFalse);
    expect(repository.invitations, isEmpty);
    final creating = model.invite(' staff@example.invalid ');
    expect(model.busy, isTrue);
    expect(await model.invite('staff@example.invalid'), isFalse);
    expect(repository.invitations, [('staff@example.invalid', 'sales')]);
    repository.pending.complete(_issued());
    expect(await creating, isTrue);
    expect(model.issued!.token, 'synthetic-secret');
    expect(model.busy, isFalse);
  });
  test('a pending invitation cannot publish after disposal', () async {
    final repository = _Repository();
    final model = TeamAccessViewModel(repository);
    await model.result;
    model.role = 'sales';
    final creating = model.invite('staff@example.invalid');
    model.dispose();
    repository.pending.complete(_issued());
    expect(await creating, isFalse);
    expect(model.issued, isNull);
  });
  test(
    'access scope changes hide issued secrets and block cached commands',
    () async {
      final repository = _Repository();
      final model = TeamAccessViewModel(repository);
      final data = await model.result;
      model.role = 'sales';
      final creating = model.invite('staff@example.invalid');
      repository.pending.complete(_issued());
      await creating;
      await model.result;
      repository.token = Object();
      expect(model.issued, isNull);
      expect(model.accepts(data), isFalse);
      expect(await model.revoke(data.invitations.single), isFalse);
      expect(repository.revocations, isEmpty);
    },
  );
  test(
    'revalidation retires an old command and clears the issued code',
    () async {
      final repository = _Repository();
      final model = TeamAccessViewModel(repository);
      await model.result;
      model.role = 'sales';
      final creating = model.invite('staff@example.invalid');
      await model.revalidate();
      repository.pending.complete(_issued());
      expect(await creating, isFalse);
      expect(model.issued, isNull);
      expect(model.busy, isFalse);
    },
  );
  test(
    'failed revoke keeps the issued code and a confirmed revoke clears it',
    () async {
      final repository = _Repository();
      final model = TeamAccessViewModel(repository);
      await model.result;
      model.role = 'sales';
      final creating = model.invite('staff@example.invalid');
      repository.pending.complete(_issued());
      await creating;
      final data = await model.result;
      repository.revokeError = const ErpException('Offline');
      expect(await model.revoke(data.invitations.single), isFalse);
      expect(model.issued, isNotNull);
      expect(model.error, contains('Offline'));
      repository.revokeError = null;
      expect(await model.revoke(data.invitations.single), isTrue);
      expect(model.issued, isNull);
    },
  );
  test(
    'repository discards a delayed team read after access invalidation',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpTeamRepository(api: api, company: 'Synthetic');
      final reading = repository.load();
      final rejected = expectLater(reading, throwsA(isA<ErpException>()));
      api.accessReady = false;
      api.loaded.complete(_team());
      await rejected;
      expect(api.calls, ['Synthetic']);
    },
  );
  test(
    'revalidation retires an old revoke outcome before permitting a new code',
    () async {
      final repository = _Repository();
      final model = TeamAccessViewModel(repository);
      await model.result;
      model.role = 'sales';
      final first = model.invite('staff@example.invalid');
      repository.pending.complete(_issued());
      await first;
      final data = await model.result;
      repository.pendingRevoke = Completer<void>();
      final old = model.revoke(data.invitations.single);
      await model.revalidate();
      expect(model.issued, isNull);
      expect(await model.invite('staff@example.invalid'), isFalse);
      repository.pendingRevoke!.complete();
      expect(await old, isFalse);
      expect(await model.invite('staff@example.invalid'), isTrue);
      await model.result;
      expect(model.issued, isNotNull);
    },
  );
  test(
    'repository rejects unusable invitation codes and quarantined commands',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpTeamRepository(api: api, company: 'Synthetic');
      api.response = {'email': 'staff@example.invalid'};
      await expectLater(
        repository.invite(email: 'staff@example.invalid', role: 'sales'),
        throwsA(isA<ErpException>()),
      );
      api.accessReady = false;
      expect(repository.scope, isNull);
      await expectLater(repository.load(), throwsA(isA<ErpException>()));
      expect(api.calls, isEmpty);
    },
  );
  test('an immediate refresh failure remains available to the view without an unhandled future', () async {
    final repository = _Repository();
    final model = TeamAccessViewModel(repository);
    await model.result;
    model.role = 'sales';
    final creating = model.invite('staff@example.invalid');
    repository.loadError = const ErpException('Offline refresh');
    repository.pending.complete(_issued());
    expect(await creating, isTrue);
    await Future<void>.delayed(Duration.zero);
    await expectLater(model.result, throwsA(isA<ErpException>()));
    expect(model.issued, isNotNull);
  });
  for (final changed in [false, true]) {
    test(
      'revalidation keeps invitation writes serialized when scope changes: $changed',
      () async {
        final repository = _Repository();
        final model = TeamAccessViewModel(repository);
        await model.result;
        model.role = 'sales';
        final first = model.invite('staff@example.invalid');
        if (changed) repository.token = Object();
        await model.revalidate();
        expect(model.busy, isTrue);
        expect(await model.invite('staff@example.invalid'), isFalse);
        expect(repository.invitations, hasLength(1));
        repository.pending.complete(_issued());
        expect(await first, isFalse);
        expect(model.busy, isFalse);
        expect(await model.invite('staff@example.invalid'), isTrue);
        expect(repository.invitations, hasLength(2));
        await model.result;
      },
    );
  }
}
