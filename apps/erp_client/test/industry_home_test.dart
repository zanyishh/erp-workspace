import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompanyApi extends ErpApi {
  _CompanyApi(this.company) : super(Uri.parse('http://localhost:8081'));
  String company;
  int generalReads = 0;
  bool configured = false;
  bool activated = false;
  final switches = <String>[];

  WorkspaceContext forCompany(String name) => WorkspaceContext.fromJson({
    'company': name,
    'companies': [
      for (final c in ['Mill', 'Books']) {'name': c},
    ],
    'setup_state': (name == 'Mill' || activated) ? 'Active' : 'General ERP',
    'knitting_enabled': name == 'Mill' || activated,
    'can_configure': true,
    'readable_records': ['Sales Order', 'Item'],
    'needs_industry_selection': name == 'New company' && !configured,
    'capabilities': ifMill(name),
  });
  List<String> ifMill(String name) =>
      (name == 'Mill' || activated) ? ['overview', 'jobs', 'production'] : [];

  @override
  Future<void> login(String username, String password) async {}
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      forCompany(company ?? this.company);
  @override
  Future<WorkspaceContext> selectCompany(String company) async {
    switches.add(company);
    this.company = company;
    return forCompany(company);
  }

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot(company, {});
  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async {
    generalReads++;
    return ErpSnapshot(company: selectedCompany!, currency: 'INR');
  }

  @override
  Future<Map<String, dynamic>> industrySettings(String company) async => {
    'state': 'Setup',
    'revision': 0,
    'settings': {
      'warehouse': 'Demo godown',
      'service_item': 'Test service',
      'fabric_item': 'Test fabric',
    },
  };
  @override
  Future<WorkspaceContext> configureIndustry(
    String company,
    Map<String, dynamic> settings,
  ) async {
    activated = settings['state'] == 'Active';
    configured = true;
    return forCompany(company);
  }
}

class _RevokedApi extends _CompanyApi {
  _RevokedApi() : super('Mill');
  bool revoked = false;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    if (!revoked) return super.workspaceContext(company: company);
    if (company == 'Mill') {
      throw const ErpException('No access.', permissionDenied: true);
    }
    return WorkspaceContext.fromJson({
      'company': 'Books',
      'companies': [
        {'name': 'Books'},
      ],
    });
  }
}

class _LimitedApi extends _CompanyApi {
  _LimitedApi() : super('Books');
  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async => ErpSnapshot(
    company: selectedCompany!,
    currency: 'INR',
    counts: {ErpModule.accounts: null, ErpModule.stock: 0},
  );
}

class _RecoveryApi extends _CompanyApi {
  _RecoveryApi() : super('Books');
  bool offline = false;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    if (offline) throw const ErpException('Connection interrupted. Try again.');
    return super.workspaceContext(company: company);
  }
}

class _OtpApi extends _CompanyApi {
  _OtpApi() : super('Books');
  int checks = 0;
  @override
  Future<void> login(String username, String password) async =>
      throw const LoginVerification(
        'synthetic-id',
        'Enter your verification code.',
      );
  @override
  Future<void> verifyLogin(
    String username,
    LoginVerification challenge,
    String code,
  ) async {
    expect(username, 'demo');
    expect(challenge.temporaryId, 'synthetic-id');
    expect(code, '012345');
    checks++;
  }
}

class _UnassignedApi extends _CompanyApi {
  _UnassignedApi() : super('Books');
  bool assigned = false;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async => assigned
      ? forCompany('Books')
      : WorkspaceContext.fromJson({'companies': []});
}

void main() {
  testWidgets(
    'first sign-in opens the workspace only after code verification',
    (tester) async {
      final api = _OtpApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(connect: (_) => api),
        ),
      );
      final signIn = tester
          .widget<SignInScreen>(find.byType(SignInScreen))
          .onSignIn;
      final attempt = signIn('demo', 'synthetic');
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Verification code'),
        '012345',
      );
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      await attempt;
      expect(api.checks, 1);
      expect(find.byType(OverviewScreen), findsOneWidget);
    },
  );

  Future<void> enter(WidgetTester tester, _CompanyApi api) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: WorkspaceShell(connect: (_) => api),
      ),
    );
    await tester
        .widget<SignInScreen>(find.byType(SignInScreen))
        .onSignIn('demo', 'test');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mill accounting clerk can open permitted business records from the same navigation',
    (tester) async {
      await enter(tester, _CompanyApi('Mill'));
      final opener = find.byTooltip('Open a business area');
      expect(opener.hitTestable(), findsOneWidget);
      await tester.tap(opener);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(PopupMenuItem<ErpModule>, 'Sales'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<ErpModule>, 'Stock'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<ErpModule>, 'Accounts'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(PopupMenuItem<ErpModule>, 'Sales'));
      await tester.pumpAndSettle();
      expect(find.text('Sales Order'), findsOneWidget);
      expect(find.byType(KnittingScreen), findsNothing);
      await tester.tap(find.byTooltip('Back to business overview'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configured mill opens directly into knitting and switches to general by company',
    (tester) async {
      final api = _CompanyApi('Mill');
      await enter(tester, api);
      expect(find.byType(KnittingScreen), findsOneWidget);
      expect(find.text('Mill overview'), findsOneWidget);
      expect(find.byType(OverviewScreen), findsNothing);
      expect(api.generalReads, 0);
      expect(find.text('Billing'), findsNothing);
      await tester.tap(find.text('General ERP'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(api.switches, isEmpty);
      expect(api.generalReads, 1);
      await tester.tap(find.text('Knitting workspace'));
      await tester.pumpAndSettle();
      expect(find.byType(KnittingScreen), findsOneWidget);
      expect(api.switches, isEmpty);
      await tester.tap(find.text('Mill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.byType(KnittingScreen), findsNothing);
      expect(api.switches, ['Books']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company switching recovers when the current company is revoked',
    (tester) async {
      final api = _RevokedApi();
      await enter(tester, api);
      api.revoked = true;
      await tester.tap(find.text('Mill'));
      await tester.pumpAndSettle();
      expect(find.text('Choose company'), findsOneWidget);
      expect(find.widgetWithText(SimpleDialogOption, 'Mill'), findsNothing);
      expect(find.widgetWithText(SimpleDialogOption, 'Books'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.byType(KnittingScreen), findsNothing);
    },
  );

  testWidgets(
    'workspace picker offers readable modules even with zero records',
    (tester) async {
      await enter(tester, _LimitedApi());
      await tester.tap(find.text('Workspaces').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Accounts'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Stock'), findsOneWidget);
    },
  );

  testWidgets(
    'renewal stays recoverable when the first access check is offline',
    (tester) async {
      final api = _RecoveryApi();
      await enter(tester, api);
      api.publishContext(api.forCompany('Books'));
      api.offline = true;
      final recovery = api.onSessionExpired!();
      // Observe callback errors as results, so a failure cannot hang the test.
      final result = recovery.then<Object>((v) => v, onError: (Object e) => e);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'synthetic');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(await result, true);
      // A changed access fingerprint rechecks the shell after authentication.
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Books',
          'access_fingerprint': 'renewed',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check access again'), findsOneWidget);
      api.offline = false;
      await tester.tap(find.text('Check access again'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new account with no assigned company can recover without signing out',
    (tester) async {
      final api = _UnassignedApi();
      await enter(tester, api);
      expect(api.generalReads, 0);
      expect(find.text('No company assigned'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      api.assigned = true;
      await tester.tap(find.text('Check access'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(api.generalReads, 1);
    },
  );

  testWidgets(
    'a general module goes back to ERP overview and keeps its workspace on company selection',
    (tester) async {
      final api = _CompanyApi('Mill');
      await enter(tester, api);
      await tester.tap(find.text('General ERP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspaces'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Selling'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to business overview'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      await tester.tap(find.text('Workspaces'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Selling'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to business overview'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      await tester.tap(find.text('Mill').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Mill'));
      await tester.pumpAndSettle();
      expect(api.switches, isEmpty);
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.byType(KnittingScreen), findsNothing);
    },
  );

  testWidgets('switching companies in General ERP stays in General ERP', (
    tester,
  ) async {
    final api = _CompanyApi('Books');
    await enter(tester, api);
    await tester.tap(find.text('Books').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Mill'));
    await tester.pumpAndSettle();
    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(find.byType(KnittingScreen), findsNothing);
  });

  testWidgets('general shell exposes its module browser at compact widths', (
    tester,
  ) async {
    final api = _CompanyApi('Books');
    await enter(tester, api);
    for (final width in [834.0, 390.0]) {
      tester.view.physicalSize = Size(width, 850);
      await tester.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.text('All modules').hitTestable(), findsOneWidget);
      expect(find.text('Knitting workspace'), findsNothing);
    }
  });

  testWidgets(
    'choosing Knitting ERP opens the mill without loading the general dashboard',
    (tester) async {
      final api = _CompanyApi('New company');
      await enter(tester, api);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Knitting ERP'));
      await tester.pumpAndSettle();
      final apply = find.text('Review & apply setup');
      await tester.dragUntilVisible(
        apply.hitTestable(),
        find.byType(ListView).first,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply setup'));
      await tester.pumpAndSettle();
      expect(find.byType(KnittingScreen), findsOneWidget);
      expect(api.generalReads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new company manager chooses the home during setup', (
    tester,
  ) async {
    final api = _CompanyApi('New company');
    await enter(tester, api);
    expect(find.byType(IndustrySetupScreen), findsOneWidget);
    expect(api.generalReads, 0);
    await tester.tap(find.widgetWithText(ChoiceChip, 'General ERP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply general workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply setup'));
    await tester.pumpAndSettle();
    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
