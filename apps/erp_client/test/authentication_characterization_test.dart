import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/session_recovery.dart';
import 'package:erp_client/sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final registration = Completer<void>();
  final signingIn = Completer<void>();
  bool closed = false;
  int registrations = 0, logins = 0;
  @override
  Future<void> registerOwner({
    required String fullName,
    required String email,
    required String password,
    required String company,
    required String industry,
  }) {
    registrations++;
    return registration.future;
  }

  @override
  Future<void> login(String username, String password) {
    logins++;
    return signingIn.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

Future<void> _fill(WidgetTester t, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await t.ensureVisible(field);
  await t.enterText(field, value);
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Widget _signIn(
  ErpApi Function() connect,
  Future<void> Function(String, String) submit,
) => MaterialApp(
  home: SignInScreen(connect: connect, onSignIn: submit, onLicenses: () {}),
);

void main() {
  testWidgets(
    'invalid account fields send no request and entry changes clear secrets',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      var requests = 0;
      await t.pumpWidget(
        _signIn(() => api, (_, _) async {
          requests++;
        }),
      );
      await _tap(t, 'Enter workspace');
      expect(find.text('Enter your username.'), findsOneWidget);
      expect(requests, 0);
      await _fill(t, 'Password', 'synthetic-secret');
      await _tap(t, 'Join with invitation');
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .controller!
            .text,
        isEmpty,
      );
      await _fill(t, 'Invitation code', 'synthetic-code');
      await _tap(t, 'Back to sign-in');
      await _tap(t, 'Join with invitation');
      expect(
        t
            .widget<TextField>(
              find.widgetWithText(TextField, 'Invitation code'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(api.registrations, 0);
    },
  );

  testWidgets(
    'an old registration cannot sign in through replacement dependencies',
    (t) async {
      final old = _Api(), next = _Api();
      addTearDown(old.close);
      addTearDown(next.close);
      final logins = <String>[];
      ErpApi oldConnect() => old;
      ErpApi newConnect() => next;
      await t.pumpWidget(
        _signIn(oldConnect, (_, _) async {
          logins.add('old');
        }),
      );
      await _tap(t, 'Create a company');
      await _fill(t, 'Full name', 'Synthetic Owner');
      await _fill(t, 'Email', 'owner@example.invalid');
      await _fill(t, 'Password', 'synthetic-password');
      await _fill(t, 'Company name', 'Synthetic Company');
      await _tap(t, 'Create workspace');
      expect(old.registrations, 1);
      await t.pumpWidget(
        _signIn(newConnect, (_, _) async {
          logins.add('new');
        }),
      );
      await t.pumpAndSettle();
      old.registration.complete();
      await t.pumpAndSettle();
      expect(logins, isEmpty);
      expect(old.closed, isTrue);
    },
  );

  testWidgets(
    'an old sign-in failure cannot overwrite replacement screen state',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      final pending = Completer<void>();
      ErpApi connect() => api;
      await t.pumpWidget(_signIn(connect, (_, _) => pending.future));
      await _fill(t, 'Username', 'owner@example.invalid');
      await _fill(t, 'Password', 'synthetic-password');
      await _tap(t, 'Enter workspace');
      await t.pumpWidget(_signIn(connect, (_, _) async {}));
      await t.pumpAndSettle();
      pending.completeError(const ErpException('Old connection failed.'));
      await t.pumpAndSettle();
      expect(find.text('Old connection failed.'), findsNothing);
    },
  );

  testWidgets('a replaced recovery dialog cannot be closed by the old login', (
    t,
  ) async {
    final old = _Api()..account = 'old@example.invalid';
    final next = _Api()..account = 'new@example.invalid';
    addTearDown(old.close);
    addTearDown(next.close);
    final selected = ValueNotifier<ErpApi>(old);
    addTearDown(selected.dispose);
    bool? restored;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                restored = await showDialog<bool>(
                  context: context,
                  builder: (_) => ValueListenableBuilder<ErpApi>(
                    valueListenable: selected,
                    builder: (_, api, _) => SessionRecoveryDialog(api: api),
                  ),
                );
              },
              child: const Text('Recover'),
            ),
          ),
        ),
      ),
    );
    await _tap(t, 'Recover');
    await _fill(t, 'Password', 'synthetic-password');
    await _tap(t, 'Sign in');
    expect(old.logins, 1);
    selected.value = next;
    await t.pumpAndSettle();
    old.signingIn.complete();
    await t.pumpAndSettle();
    expect(restored, isNull);
    expect(find.byType(SessionRecoveryDialog), findsOneWidget);
    expect(find.text('new@example.invalid'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.widgetWithText(TextField, 'Password'))
          .controller!
          .text,
      isEmpty,
    );
  });
}
