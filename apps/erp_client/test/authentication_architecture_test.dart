import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/authentication/data/erp_onboarding_repository.dart';
import 'package:erp_client/features/authentication/data/erp_session_repository.dart';
import 'package:erp_client/features/authentication/data/onboarding_repository.dart';
import 'package:erp_client/features/authentication/data/session_repository.dart';
import 'package:erp_client/features/authentication/models/authentication.dart';
import 'package:erp_client/features/authentication/presentation/sign_in_view_model.dart';
import 'package:erp_client/features/authentication/presentation/session_login_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _values = SignInValues(
  username: ' owner@example.invalid ',
  password: 'synthetic-password',
  fullName: ' Synthetic Owner ',
  company: ' Synthetic Company ',
  invitation: ' synthetic-code ',
);

class _Onboarding implements OnboardingRepository {
  final calls = <String>[];
  Completer<void>? pending;
  @override
  Future<void> registerOwner(
    SignInValues values, {
    required String industry,
  }) async {
    calls.add('owner/$industry');
    await pending?.future;
  }

  @override
  Future<void> joinNew(SignInValues values) async {
    calls.add('new');
    await pending?.future;
  }

  @override
  Future<void> joinExisting(SignInValues values) async {
    calls.add('existing');
    await pending?.future;
  }
}

class _Session implements SessionRepository {
  @override
  String account = 'owner@example.invalid';
  @override
  Object identity = Object();
  int logins = 0;
  final codes = <String>[];
  LoginVerification? challenge;
  Object? failure;
  Completer<LoginVerification?>? pendingLogin;
  Completer<void>? pendingCode;
  @override
  Future<LoginVerification?> signIn(String username, String password) async {
    logins++;
    if (failure case final error?) throw error;
    return pendingLogin?.future ?? challenge;
  }

  @override
  Future<void> verify(
    String username,
    LoginVerification challenge,
    String code,
  ) async {
    codes.add(code);
    if (failure case final error?) throw error;
    await pendingCode?.future;
  }
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  bool closed = false;
  final registrations = <(String, String, String)>[];
  Object? failure;
  @override
  Future<void> registerOwner({
    required String fullName,
    required String email,
    required String password,
    required String company,
    required String industry,
  }) async {
    registrations.add((fullName, email, company));
    if (failure case final error?) throw error;
  }

  @override
  Future<void> login(String user, String password) async =>
      throw const LoginVerification('synthetic-id', 'Synthetic challenge');
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test(
    'a created account retries sign-in without replaying registration',
    () async {
      final repository = _Onboarding();
      var attempts = 0;
      final model = SignInViewModel(
        repository,
        signIn: (username, password) async {
          expect(username, 'owner@example.invalid');
          attempts++;
          if (attempts == 1) throw const ErpException('Offline');
        },
      );
      model.selectEntry(SignInEntry.owner);
      expect(await model.submit(_values), SignInResult.signInRequired);
      expect(model.entry, SignInEntry.signIn);
      expect(
        model.error,
        contains('Your company was created. Sign in to continue.'),
      );
      expect(await model.submit(_values), SignInResult.signedIn);
      expect(repository.calls, ['owner/general']);
      expect(attempts, 2);
    },
  );
  for (final existing in [false, true]) {
    test('invitation redemption selects existing account: $existing', () async {
      final repository = _Onboarding();
      final model = SignInViewModel(repository, signIn: (_, _) async {});
      model.selectEntry(SignInEntry.join);
      if (existing) model.toggleExisting();
      expect(await model.submit(_values), SignInResult.signedIn);
      expect(repository.calls, [existing ? 'existing' : 'new']);
    });
  }
  test(
    'onboarding commands are serialized and disposed work cannot sign in',
    () async {
      final repository = _Onboarding()..pending = Completer<void>();
      var signIns = 0;
      final model = SignInViewModel(
        repository,
        signIn: (_, _) async {
          signIns++;
        },
      );
      model.selectEntry(SignInEntry.owner);
      final first = model.submit(_values);
      expect(model.busy, isTrue);
      expect(await model.submit(_values), SignInResult.ignored);
      model.dispose();
      repository.pending!.complete();
      expect(await first, SignInResult.ignored);
      expect(signIns, 0);
      expect(repository.calls, hasLength(1));
    },
  );
  test('entry and existing-account changes clear errors and preserve industry choice', () async {
    final repository = _Onboarding();
    final model = SignInViewModel(
      repository,
      signIn: (_, _) async {
        throw const ErpException('Offline');
      },
    );
    await model.submit(_values);
    expect(model.error, contains('Offline'));
    model.industry = 'knitting';
    model.selectEntry(SignInEntry.join);
    expect(model.error, isNull);
    model.toggleExisting();
    expect(model.existingAccount, isTrue);
    model.selectEntry(SignInEntry.owner);
    expect(model.existingAccount, isFalse);
    expect(model.industry, 'knitting');
  });
  test(
    'session challenges require an explicit code and serialize verification',
    () async {
      final repository = _Session()
        ..challenge = const LoginVerification('id', 'Enter code');
      final model = SessionLoginViewModel(repository);
      expect(
        await model.signIn(repository.account, 'synthetic'),
        LoginResult.verificationRequired,
      );
      expect(model.busy, isTrue);
      expect(
        await model.signIn(repository.account, 'synthetic'),
        LoginResult.ignored,
      );
      final verification = model.verification;
      expect(await verification.verify('  '), isFalse);
      expect(repository.codes, isEmpty);
      repository.pendingCode = Completer<void>();
      final first = verification.verify(' 012345 ');
      expect(await verification.verify('012345'), isFalse);
      expect(repository.codes, ['012345']);
      repository.pendingCode!.complete();
      expect(await first, isTrue);
      expect(model.busy, isFalse);
    },
  );
  test(
    'verification errors permit retry without a second login or challenge',
    () async {
      final repository = _Session()
        ..challenge = const LoginVerification('id', 'Enter code');
      final model = SessionLoginViewModel(repository);
      await model.signIn(repository.account, 'synthetic');
      repository.failure = const ErpException('Check code');
      expect(await model.verification.verify('wrong'), isFalse);
      expect(model.verification.error, contains('Check code'));
      repository.failure = null;
      expect(await model.verification.verify('012345'), isTrue);
      expect(repository.logins, 1);
    },
  );
  test('recovery never authenticates a different account and preserves failure flags', () async {
    final repository = _Session();
    final model = SessionLoginViewModel(
      repository,
      recoveryAccount: repository.account,
    );
    repository.account = 'another@example.invalid';
    expect(
      await model.signIn('owner@example.invalid', 'synthetic'),
      LoginResult.failed,
    );
    expect(repository.logins, 0);
    const denied = ErpException('Denied', permissionDenied: true);
    final normal = SessionLoginViewModel(repository);
    repository.failure = denied;
    expect(
      await normal.signIn(repository.account, 'synthetic'),
      LoginResult.failed,
    );
    expect(identical(normal.failure, denied), isTrue);
  });
  test('disposing a login also invalidates its verification model', () async {
    final repository = _Session()
      ..challenge = const LoginVerification('id', 'Enter code');
    final model = SessionLoginViewModel(repository);
    await model.signIn(repository.account, 'synthetic');
    final verification = model.verification;
    model.dispose();
    expect(await verification.verify('012345'), isFalse);
    expect(repository.codes, isEmpty);
  });
  test(
    'a disposed or replaced session cannot publish its delayed login',
    () async {
      final repository = _Session()
        ..pendingLogin = Completer<LoginVerification?>();
      final model = SessionLoginViewModel(repository);
      final first = model.signIn(repository.account, 'synthetic');
      model.dispose();
      repository.pendingLogin!.complete();
      expect(await first, LoginResult.ignored);
    },
  );
  test('the onboarding adapter trims fields and always closes its temporary service', () async {
    for (final fail in [false, true]) {
      final api = _Api();
      if (fail) api.failure = const ErpException('Unavailable');
      final repository = ErpOnboardingRepository(
        connect: () => api,
        authenticate: (_, _, _) async {},
      );
      final operation = repository.registerOwner(_values, industry: 'general');
      if (fail) {
        await expectLater(operation, throwsA(isA<ErpException>()));
      } else {
        await operation;
      }
      expect(api.closed, isTrue);
      expect(api.registrations, [
        ('Synthetic Owner', 'owner@example.invalid', 'Synthetic Company'),
      ]);
    }
  });
  test(
    'the session repository exposes a challenge without losing its identity',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpSessionRepository(api);
      final identity = repository.identity;
      final challenge = await repository.signIn(
        'owner@example.invalid',
        'synthetic',
      );
      expect(challenge!.temporaryId, 'synthetic-id');
      expect(repository.identity, identity);
    },
  );
}
