import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/team_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final invites = <(String, String, String)>[];
  final revokes = <(String, String)>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> team(String company) async => {
    'members': [
      {'email': '$company-member@example.invalid', 'role': 'sales'},
    ],
    'roles': [
      {'key': 'sales', 'label': 'Sales'},
    ],
    'invitations': [
      {
        'name': '$company-invitation',
        'email': 'pending@example.invalid',
        'role': 'sales',
        'expires_at': '2031-04-18',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> inviteMember(
    String company,
    String email,
    String role,
  ) async {
    invites.add((company, email, role));
    return pending?.future ??
        {'token': 'synthetic-$company-code', 'email': email, 'role': role};
  }

  @override
  Future<void> revokeInvitation(String company, String name) async {
    revokes.add((company, name));
  }
}

Future<void> _show(WidgetTester t, _Api api, String company) async {
  await t.pumpWidget(
    MaterialApp(
      home: TeamAccessScreen(api: api, company: company),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _fill(WidgetTester t) async {
  final email = find.widgetWithText(TextField, 'Staff email');
  await t.ensureVisible(email);
  await t.enterText(email, 'staff@example.invalid');
  final role = find.byType(DropdownButtonFormField<String>);
  await t.ensureVisible(role);
  await t.tap(role);
  await t.pumpAndSettle();
  await t.tap(find.text('Sales').last);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Create invitation'));
}

void main() {
  testWidgets(
    'invalid invitation fields send no command and a valid invitation sends once',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await _show(t, api, 'A');
      await t.ensureVisible(find.text('Create invitation'));
      await t.tap(find.text('Create invitation'));
      await t.pumpAndSettle();
      expect(api.invites, isEmpty);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await _fill(t);
      api.pending = Completer<Map<String, dynamic>>();
      await t.tap(find.text('Create invitation'));
      await t.pump();
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create invitation'),
      );
      expect(button.onPressed, isNull);
      expect(api.invites, [('A', 'staff@example.invalid', 'sales')]);
      api.pending!.complete({
        'token': 'synthetic-A-code',
        'email': 'staff@example.invalid',
      });
      await t.pumpAndSettle();
      expect(find.text('Invitation ready'), findsOneWidget);
    },
  );

  testWidgets('revoke requires confirmation and keeps the invitation company', (
    t,
  ) async {
    final api = _Api();
    addTearDown(api.close);
    await _show(t, api, 'A');
    await t.ensureVisible(find.byTooltip('Revoke invitation'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Revoke invitation'));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep invitation'));
    await t.pumpAndSettle();
    expect(api.revokes, isEmpty);
    await t.tap(find.byTooltip('Revoke invitation'));
    await t.pumpAndSettle();
    await t.tap(find.text('Revoke'));
    await t.pumpAndSettle();
    expect(api.revokes, [('A', 'A-invitation')]);
  });

  testWidgets(
    'company replacement removes issued codes and loads the new team',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await _show(t, api, 'A');
      await _fill(t);
      await t.tap(find.text('Create invitation'));
      await t.pumpAndSettle();
      expect(find.text('synthetic-A-code'), findsOneWidget);
      await _show(t, api, 'B');
      expect(find.text('synthetic-A-code'), findsNothing);
      expect(find.text('B-member@example.invalid'), findsOneWidget);
      expect(find.text('A-member@example.invalid'), findsNothing);
    },
  );

  testWidgets(
    'an invitation completing for the old company cannot reveal its code',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      api.pending = Completer<Map<String, dynamic>>();
      await _show(t, api, 'A');
      await _fill(t);
      await t.tap(find.text('Create invitation'));
      await t.pump();
      await _show(t, api, 'B');
      api.pending!.complete({
        'token': 'old-company-secret',
        'email': 'staff@example.invalid',
      });
      await t.pumpAndSettle();
      expect(find.text('old-company-secret'), findsNothing);
      expect(find.text('B-member@example.invalid'), findsOneWidget);
      expect(find.text('Create invitation'), findsOneWidget);
    },
  );

  testWidgets(
    'a revoke dialog from the old company cannot command the new company',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await _show(t, api, 'A');
      await t.ensureVisible(find.byTooltip('Revoke invitation'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Revoke invitation'));
      await t.pumpAndSettle();
      await _show(t, api, 'B');
      await t.tap(find.text('Revoke'));
      await t.pumpAndSettle();
      expect(api.revokes, isEmpty);
    },
  );
}
