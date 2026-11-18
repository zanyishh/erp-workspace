import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/team_access.dart';
import 'package:erp_client/ui/workspace_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestApi extends ErpApi {
  _GuestApi() : super(Uri.parse('http://localhost:8081'));
  String? registered, accepted;
  @override
  Future<Map<String, dynamic>> team(String company) async => {
    'members': [
      for (int i = 0; i < 10; i++)
        {'email': 'member$i@example.invalid', 'role': 'sales'},
    ],
    'invitations': [],
    'roles': [
      {'key': 'sales', 'label': 'Sales'},
    ],
  };

  @override
  Future<Map<String, dynamic>> inviteMember(
    String company,
    String email,
    String role,
  ) async => {'email': email, 'token': 'synthetic-invitation-code'};

  @override
  Future<void> registerOwner({
    required String fullName,
    required String email,
    required String password,
    required String company,
    required String industry,
  }) async {
    registered = '$company/$industry';
  }

  @override
  Future<void> acceptInvitation(
    String token, {
    String? fullName,
    String? email,
    String? password,
  }) async {
    accepted = '$email/$token';
  }
}

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets(
      'workspace choice selects the studio illustration at width $width',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 840);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        await t.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: SignInScreen(
              connect: _GuestApi.new,
              onSignIn: (_, _) async {},
              onLicenses: () {},
            ),
          ),
        );
        await t.ensureVisible(find.text('Create a company'));
        await t.tap(find.text('Create a company'));
        await t.pumpAndSettle();
        expect(
          t.widget<WorkspaceArt>(find.byType(WorkspaceArt)).object,
          ArtObject.warehouse,
        );
        final selection = find.byType(DropdownButtonFormField<String>);
        await t.ensureVisible(selection);
        await t.tap(selection);
        await t.pumpAndSettle();
        await t.tap(find.text('Knitting').last);
        await t.pumpAndSettle();
        expect(
          t.widget<WorkspaceArt>(find.byType(WorkspaceArt)).object,
          ArtObject.machine,
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('after inviting from a short phone the confirmation is in view', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 430);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: TeamAccessScreen(api: _GuestApi(), company: 'Sample Mill'),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Staff email'),
      'staff@example.invalid',
    );
    final role = find.byType(DropdownButtonFormField<String>);
    await t.ensureVisible(role);
    await t.tap(role);
    await t.pumpAndSettle();
    await t.tap(find.text('Sales').last);
    await t.pumpAndSettle();
    final submit = find.text('Create invitation');
    await t.ensureVisible(submit);
    await t.tap(submit);
    await t.pumpAndSettle();
    expect(find.text('Invitation ready'), findsOneWidget);
    expect(find.textContaining('setState() callback'), findsNothing);
    final title = t.getRect(find.text('Invitation ready'));
    expect(
      title.top,
      greaterThanOrEqualTo(t.getBottomLeft(find.byType(AppBar)).dy),
    );
    expect(title.bottom, lessThanOrEqualTo(t.view.physicalSize.height));
    final copy = find.widgetWithText(OutlinedButton, 'Copy code');
    expect(copy.hitTestable(), findsOneWidget);
    String? copied;
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await t.tap(copy);
    await t.pumpAndSettle();
    expect(copied, 'synthetic-invitation-code');
    expect(find.text('Code copied'), findsOneWidget);
  });

  for (final owner in [true, false]) {
    testWidgets(
      owner ? 'a created company can sign in again if its first login fails' : 'joined staff can retry login without redeeming the invitation twice',
      (t) async {
        final api = _GuestApi();
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(360, 640);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetViewInsets);
        var logins = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: SignInScreen(
              connect: () => api,
              onSignIn: (username, password) async {
                expect(username, 'person@example.invalid');
                logins++;
                if (logins == 1) {
                  throw const ErpException('Connection interrupted.');
                }
              },
              onLicenses: () {},
            ),
          ),
        );
        Future<void> tap(String label) async {
          final target = find.text(label);
          await t.ensureVisible(target.last);
          await t.tap(target.last);
          await t.pumpAndSettle();
        }

        Future<void> fill(String label, String text) async {
          final field = find.widgetWithText(TextField, label);
          await t.ensureVisible(field);
          await t.enterText(field, text);
          await t.pump();
        }

        await tap(owner ? 'Create a company' : 'Join with invitation');
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Enter workspace'), findsOneWidget);
        await tap(owner ? 'Create a company' : 'Join with invitation');
        t.view.viewInsets = const FakeViewPadding(bottom: 260);
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(4));
        expect(find.text('ERPNext address'), findsNothing);
        await fill('Full name', 'Example Person');
        await fill('Email', 'person@example.invalid');
        await fill('Password', 'example password');
        if (owner) {
          await fill('Company name', 'Example Company');
        } else {
          expect(find.text('Company name'), findsNothing);
          expect(find.text('General ERP'), findsNothing);
          await fill('Invitation code', 'example-code');
        }
        await tap(owner ? 'Create workspace' : 'Join workspace');
        expect(logins, 1);
        if (owner) {
          expect(api.registered, 'Example Company/general');
          expect(
            find.textContaining('Your company was created.'),
            findsOneWidget,
          );
        } else {
          expect(api.accepted, 'person@example.invalid/example-code');
          expect(
            find.textContaining('You joined the company.'),
            findsOneWidget,
          );
        }
        expect(find.text('Username'), findsOneWidget);
        await fill('Password', 'example password');
        await tap('Enter workspace');
        expect(logins, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
