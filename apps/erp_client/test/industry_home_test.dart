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

void main() {
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
        .onSignIn('http://localhost:8081', 'demo', 'test');
    await tester.pumpAndSettle();
  }

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
      await tester.tap(find.text('Back to mill'));
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
      expect(find.text('Back to mill'), findsNothing);
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
