// Connected rehearsal of the installed app's account and invitation screens.
// Run only against the synthetic site exposed by scripts/setup-native-test.command.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:erp_client/design.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/team_access.dart';
import 'package:erp_client/ui/workspace_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _PilotApi extends ErpApi {
  _PilotApi(super.uri);
  bool closed = false;
  @override
  void close() {
    super.close();
    closed = true;
  }
}

void main() {
  _ConnectedBinding();
  for (final knitting in [false, true]) {
    final industry = knitting ? 'Knitting' : 'General ERP';
    testWidgets('owner creates $industry and invites a scoped staff member', (
      t,
    ) async {
      final uri = Uri.parse('http://localhost:8081');
      final admin = ErpApi(uri);
      final verified = await t.runAsync(() async {
        try {
          await admin.login(
            'Administrator',
            Platform.environment['ERP_LOCAL_PILOT_PASSWORD'] ??
                (throw StateError(
                  'Set ERP_LOCAL_PILOT_PASSWORD for the synthetic local site.',
                )),
          );
          final site = (await admin.nativeCatalog()).site;
          await admin.signOut();
          return site;
        } finally {
          admin.close();
        }
      });
      expect(verified, 'native-test.localhost');
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final company = 'Pilot ${knitting ? "Mill" : "Trade"} $stamp';
      final owner = 'pilot-owner-$stamp@example.invalid';
      final customer = 'Pilot Customer $stamp';
      String? job;
      final staff = 'pilot-staff-$stamp@example.invalid';
      final password = base64Url.encode(
        List.generate(24, (_) => Random.secure().nextInt(256)),
      );
      late _PilotApi current;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);

      Future<void> wait(Finder what) async {
        for (var i = 0; i < 450; i++) {
          await t.pump(const Duration(milliseconds: 70));
          if (what.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 70)),
          );
        }
        final notes = t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .where(
              (v) =>
                  v != password &&
                  v.length > 8 &&
                  !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(v),
            )
            .toList();
        fail('Waiting for $what in $industry: $notes');
      }

      Future<void> tap(Finder what) async {
        await wait(what);
        await t.ensureVisible(what.first);
        await t.pump(const Duration(milliseconds: 350));
        await t.tap(what.first);
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> press(String label) => tap(find.text(label));
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextField, label);
        await t.ensureVisible(field);
        await t.enterText(field, value);
        await t.pump();
      }

      Future<void> account() async {
        if (knitting) {
          await tap(find.byTooltip('Account'));
        } else {
          await tap(find.byTooltip('Workspace options'));
          await press('Account and settings');
        }
        await wait(find.text('Sign out'));
        expect(find.text('Open original ERPNext'), findsNothing);
      }

      Future<void> signOut() async {
        final previous = current;
        await press('Sign out');
        await wait(find.byType(SignInScreen));
        // The shell clears its UI immediately, then revokes the server session.
        for (var i = 0; !previous.closed && i < 200; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 30));
        }
        expect(previous.closed, isTrue);
      }

      Future<void> home({required bool isOwner}) async {
        await wait(find.byType(knitting ? KnittingScreen : OverviewScreen));
        final workspace = await t.runAsync(() => current.workspaceContext());
        expect(workspace!.company, company);
        expect(workspace.companies.map((c) => c['name']), [company]);
        expect(workspace.enabled, knitting);
        expect(workspace.needsIndustrySelection, isFalse);
        expect(workspace.canManageTeam, isOwner);
        if (knitting && !isOwner) {
          expect(workspace.capabilities, contains('production'));
          expect(workspace.capabilities, isNot(contains('billing')));
        }
        expect(find.byType(IndustrySetupScreen), findsNothing);
      }

      final screenshotDir = Platform.environment['ERP_PILOT_SCREENSHOTS'];
      final surface = GlobalKey();
      if (screenshotDir != null) {
        for (final font in {
          'Manrope': 'assets/fonts/Manrope-Regular.ttf',
          'BarlowCondensed': 'assets/fonts/BarlowCondensed-SemiBold.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      }
      Future<void> capture(String name) async {
        if (screenshotDir == null) return;
        await t.pump(const Duration(milliseconds: 250));
        final art = find.byType(WorkspaceArt);
        final source = t.widget<Image>(
          find.descendant(of: art, matching: find.byType(Image)),
        );
        await t.runAsync(() => precacheImage(source.image, t.element(art)));
        await wait(
          find.descendant(
            of: art,
            matching: find.byWidgetPredicate(
              (w) => w is RawImage && w.image != null,
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 600));
        final boundary =
            surface.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await Directory(screenshotDir).create(recursive: true);
          await File('$screenshotDir/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await t.pumpWidget(
        RepaintBoundary(
          key: surface,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WorkspaceTheme.theme,
            home: WorkspaceShell(
              connect: (configured) {
                expect(configured, uri);
                return current = _PilotApi(uri);
              },
            ),
          ),
        ),
      );
      await press('Create a company');
      await fill('Full name', 'Pilot Owner');
      await fill('Email', owner);
      await fill('Password', password);
      await fill('Company name', company);
      if (knitting) {
        await tap(find.byType(DropdownButtonFormField<String>));
        await press('Knitting');
      }
      if (knitting) await capture('owner-signup');
      await press('Create workspace');
      await home(isOwner: true);
      if (knitting) {
        await press('Jobs');
        await press('New job');
        await tap(
          find.byWidgetPredicate(
            (w) => w is InputDecorator && w.decoration.labelText == 'Customer',
          ),
        );
        await press('Create customer');
        await wait(find.byType(DocumentFields));
        Future<void> documentField(String key, String value) async {
          final field = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          );
          await t.ensureVisible(field);
          await t.enterText(field, value);
          await t.pump();
        }

        await documentField('customer_name', customer);
        await documentField('customer_group', 'Commercial');
        await documentField('territory', 'India');
        await press('Save');
        await wait(
          find.descendant(
            of: find.byType(KnittingCommandForm),
            matching: find.textContaining(customer),
          ),
        );
        await t.pump(const Duration(milliseconds: 500));
        Future<void> jobField(
          String label,
          String text, {
          int index = 0,
        }) async {
          final field = find
              .byWidgetPredicate(
                (w) => w is TextField && w.decoration?.labelText == label,
              )
              .at(index);
          await t.ensureVisible(field);
          await t.enterText(field, text);
          await t.pump();
        }

        await jobField('Target · kg', '12');
        await jobField('Rate per kg', '100');
        await press('Add fabric programme');
        await jobField('Fabric', 'Pilot single jersey');
        await jobField('Colour', 'Natural');
        await jobField('Target · kg', '12', index: 1);
        await press('Review entry');
        await press('Confirm & post');
        await wait(find.text('SAVED IN ERP'));
        job = t
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data ?? '')
            .firstWhere((s) => s.startsWith('Job · '))
            .substring(6);
        await press('Done');
        expect(job, isNotEmpty);
      }
      await account();
      await press('Team access');
      await wait(find.text('Invite a teammate'));
      await fill('Staff email', staff);
      await tap(find.byType(DropdownButtonFormField<String>));
      await press(knitting ? 'Knitting operator' : 'Sales');
      if (knitting) await capture('invite-staff');
      await press('Create invitation');
      await wait(find.byKey(const ValueKey('invitation-code')));
      final code = t
          .widget<SelectableText>(find.byKey(const ValueKey('invitation-code')))
          .data!;
      expect(code, isNotEmpty);
      await press('Copy code');
      await wait(find.text('Code copied'));
      await wait(find.text('Pending invitations · 1'));
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 350));
      await account();
      await signOut();
      await press('Join with invitation');
      expect(find.text('Company name'), findsNothing);
      expect(find.text('Industry'), findsNothing);
      if (knitting) await capture('join-invitation');
      await fill('Invitation code', code);
      await fill('Full name', 'Pilot Staff');
      await fill('Email', staff);
      await fill('Password', password);
      await press('Join workspace');
      await home(isOwner: false);
      if (knitting) {
        final snapshot = await t.runAsync(
          () => current.knittingSnapshot(company, job: job),
        );
        expect(snapshot!.rows('jobs').single['name'], job);
        expect(snapshot.rows('jobs').single['customer'], isNotEmpty);
        debugPrint('Operator opened $job for the new owner-created customer.');
      }
      await account();
      expect(find.text('Team access'), findsNothing);
      await signOut();
      await fill('Username', owner);
      await fill('Password', password);
      await press('Enter workspace');
      await home(isOwner: true);
      await account();
      await press('Team access');
      await wait(find.text('Members · 2'));
      await wait(find.text('Pending invitations · 0'));
      expect(find.text('Pilot Staff'), findsOneWidget);
      expect(find.byType(TeamAccessScreen), findsOneWidget);
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 350));
      await account();
      await signOut();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 30));
      debugPrint(
        'Verified native-test.localhost: $company, invited ${knitting ? "Knitting operator" : "Sales"}, 2 members, 0 pending.',
      );
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
