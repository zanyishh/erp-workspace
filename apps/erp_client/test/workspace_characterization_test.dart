import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext _context(String company) => WorkspaceContext.fromJson({
  'company': company,
  'companies': [
    {'name': company},
  ],
  'can_manage_team': true,
  'readable_records': ['Sales Invoice'],
});

class _Api extends ErpApi {
  _Api(this.company) : super(Uri.parse('http://127.0.0.1:8081'));
  final String company;
  final logins = <String>[];
  int contextReads = 0, registrations = 0;
  bool closed = false;
  Completer<void>? loginPending, registrationPending;
  Completer<WorkspaceContext>? contextPending;
  @override
  Future<void> login(String username, String password) async {
    logins.add(username);
    await loginPending?.future;
  }

  @override
  Future<void> registerOwner({
    required String fullName,
    required String email,
    required String password,
    required String company,
    required String industry,
  }) async {
    registrations++;
    await registrationPending?.future;
  }

  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    contextReads++;
    return contextPending?.future ?? _context(this.company);
  }

  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async => ErpSnapshot(
    company: company,
    currency: 'INR',
    counts: {ErpModule.accounts: 0},
  );
  @override
  void close() {
    closed = true;
    super.close();
  }
}

WorkspaceContext _multiple(String company, {int revision = 0}) =>
    WorkspaceContext.fromJson({
      'company': company,
      'companies': [
        {'name': 'A'},
        {'name': 'B'},
      ],
      'can_manage_team': true,
      'revision': revision,
    });

class _SwitchingApi extends _Api {
  _SwitchingApi() : super('A') {
    publishContext(_multiple('B', revision: 1));
  }
  bool selecting = false;
  final stale = Completer<WorkspaceContext>();
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    final value = selecting && company == 'A'
        ? await stale.future
        : _multiple(company ?? 'A');
    publishContext(value);
    return value;
  }

  @override
  Future<WorkspaceContext> selectCompany(String company) async {
    selecting = true;
    final value = _multiple(company, revision: 2);
    publishContext(value);
    return value;
  }

  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async => ErpSnapshot(
    company: selectedCompany ?? 'A',
    currency: 'INR',
    counts: {ErpModule.accounts: 0},
  );
}

Widget _shell(
  ErpApi Function(Uri) connect, {
  Future<LocalWorkspace> Function()? local,
}) => MaterialApp(
  theme: WorkspaceTheme.theme,
  home: WorkspaceShell(connect: connect, openLocal: local),
);
Future<void> _fill(WidgetTester t, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await t.ensureVisible(field);
  await t.enterText(field, value);
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
  await t.pump();
  await t.tap(find.text(label).last);
  await t.pump();
}

void _desktop(WidgetTester t) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1440, 1000);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'replacing the shell factory retires pending registration credentials',
    (t) async {
      _desktop(t);
      final old = _Api('Old Company')..registrationPending = Completer<void>();
      final next = _Api('New Company');
      addTearDown(old.close);
      addTearDown(next.close);
      ErpApi first(Uri _) => old;
      ErpApi second(Uri _) => next;
      await t.pumpWidget(_shell(first));
      await t.pumpAndSettle();
      await _tap(t, 'Create a company');
      await t.pumpAndSettle();
      await _fill(t, 'Full name', 'Synthetic Owner');
      await _fill(t, 'Email', 'owner@example.invalid');
      await _fill(t, 'Password', 'synthetic-password');
      await _fill(t, 'Company name', 'Old Company');
      await _tap(t, 'Create workspace');
      expect(old.registrations, 1);
      await t.pumpWidget(_shell(second));
      await t.pump();
      old.registrationPending!.complete();
      await t.pumpAndSettle();
      expect(next.logins, isEmpty);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(old.closed, isTrue);
    },
  );
  for (final phase in ['login', 'context']) {
    testWidgets('factory replacement rejects a delayed old $phase completion', (
      t,
    ) async {
      _desktop(t);
      final old = _Api('Old Company'), next = _Api('New Company');
      if (phase == 'login') {
        old.loginPending = Completer<void>();
      } else {
        old.contextPending = Completer<WorkspaceContext>();
      }
      addTearDown(old.close);
      addTearDown(next.close);
      ErpApi first(Uri _) => old;
      ErpApi second(Uri _) => next;
      await t.pumpWidget(_shell(first));
      await t.pumpAndSettle();
      await _fill(t, 'Username', 'owner@example.invalid');
      await _fill(t, 'Password', 'synthetic-password');
      await _tap(t, 'Enter workspace');
      expect(old.logins, hasLength(1));
      await t.pumpWidget(_shell(second));
      await t.pump();
      if (phase == 'login') {
        old.loginPending!.complete();
      } else {
        old.contextPending!.complete(_context(old.company));
      }
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(OverviewScreen), findsNothing);
      expect(old.closed, isTrue);
      expect(next.logins, isEmpty);
    });
  }
  testWidgets(
    'replacing a pending local opener publishes only its replacement',
    (t) async {
      _desktop(t);
      final old = _Api('Old Company'), next = _Api('New Company');
      addTearDown(old.close);
      addTearDown(next.close);
      final pending = Completer<LocalWorkspace>();
      ErpApi connect(Uri _) => next;
      Future<LocalWorkspace> first() => pending.future;
      Future<LocalWorkspace> second() async =>
          LocalWorkspace(next, next.company);
      await t.pumpWidget(_shell(connect, local: first));
      await t.pump();
      await t.pumpWidget(_shell(connect, local: second));
      await t.pump();
      pending.complete(LocalWorkspace(old, old.company));
      await t.pumpAndSettle();
      final overview = t.widget<OverviewScreen>(find.byType(OverviewScreen));
      expect(overview.data.company, 'New Company');
      expect(old.closed, isTrue);
    },
  );
  testWidgets(
    'a permission refresh during company selection cannot restore the old company',
    (t) async {
      _desktop(t);
      final api = _SwitchingApi();
      addTearDown(api.close);
      ErpApi connect(Uri _) => api;
      await t.pumpWidget(_shell(connect));
      await t.pumpAndSettle();
      await _fill(t, 'Username', 'owner@example.invalid');
      await _fill(t, 'Password', 'synthetic-password');
      await _tap(t, 'Enter workspace');
      await t.pumpAndSettle();
      await t.tap(find.text('A').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SimpleDialogOption, 'B'));
      await t.pump();
      await t.pump();
      expect(api.selecting, isTrue);
      api.stale.complete(_multiple('A'));
      await t.pumpAndSettle();
      expect(find.text('Access check'), findsNothing);
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'B',
      );
    },
  );
}
