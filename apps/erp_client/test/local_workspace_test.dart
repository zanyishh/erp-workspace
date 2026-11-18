import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _companies = [
  {'name': 'Meridian Trading', 'industry': 'general'},
  {'name': 'Kaveri Loomworks', 'industry': 'knitting'},
];

class _LocalApi extends ErpApi {
  _LocalApi(this.company) : super(Uri.parse('http://127.0.0.1:8081'));
  final String company;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    expect(company, this.company);
    return WorkspaceContext.fromJson({
      'company': this.company,
      'companies': [
        {'name': this.company},
      ],
      'can_manage_team': true,
      'knitting_enabled': this.company == 'Kaveri Loomworks',
      'readable_records': ['Sales Invoice'],
      'capabilities': this.company == 'Kaveri Loomworks'
          ? ['overview', 'jobs']
          : [],
    });
  }

  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async => ErpSnapshot(
    company: selectedCompany!,
    currency: 'INR',
    counts: {ErpModule.accounts: 3},
  );
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async {
    expect(company, this.company);
    return KnittingSnapshot(company, {});
  }

  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) async {
    expect(company, this.company);
    return {
      'rows': [],
      'statuses': ['All'],
      'has_more': false,
      'can_create': false,
    };
  }
}

class _MultiCompanyApi extends _LocalApi {
  _MultiCompanyApi(super.company);
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      WorkspaceContext.fromJson({
        'company': this.company,
        'companies': [
          for (final name in [
            'Archive One',
            'Archive Two',
            'Archive Three',
            'Archive Four',
          ])
            {'name': name},
        ],
        'can_manage_team': false,
        'can_read_imported_history': true,
        'readable_records': ['Sales Invoice'],
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'explicit local opt-out uses the normal sign-in entry',
    (t) async {
      await t.pumpWidget(const ErpWorkspaceApp());
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
    },
    skip: const bool.fromEnvironment('ERP_LOCAL_WORKSPACE', defaultValue: true),
  );

  testWidgets(
    'local launch retries without credentials and opens the General company',
    (t) async {
      var attempts = 0;
      final api = _LocalApi('Meridian Trading');
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            openLocal: () async {
              attempts++;
              if (attempts == 1) {
                throw const ErpException('Local service unavailable.');
              }
              return LocalWorkspace(
                api,
                'Meridian Trading',
                companies: _companies,
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.text('Retry connection'), findsOneWidget);
      await t.tap(find.text('Retry connection'));
      await t.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Meridian Trading',
      );
      expect(find.text('Knitting workspace'), findsNothing);
      expect(find.byType(KnittingScreen), findsNothing);
      expect(find.byType(SignInScreen), findsNothing);
      expect(attempts, 2);
    },
  );

  testWidgets(
    'company selection changes local account, industry and invoice company together',
    (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final opened = <_LocalApi>[];
      Future<LocalWorkspace> open(String company) async {
        final api = _LocalApi(company);
        opened.add(api);
        return LocalWorkspace(api, company, companies: _companies);
      }

      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            openLocal: () => open('Meridian Trading'),
            openLocalCompany: open,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.text('Knitting workspace'), findsNothing);
      await t.tap(find.text('Invoices').first);
      await t.pumpAndSettle();
      final generalHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
      expect(generalHub.company, 'Meridian Trading');
      expect(generalHub.api, same(opened.first));
      expect(find.text('Kaveri Loomworks'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Meridian Trading').first);
      await t.pumpAndSettle();
      expect(find.text('Open knitting workspace'), findsNothing);
      await t.tap(find.widgetWithText(SimpleDialogOption, 'Kaveri Loomworks'));
      await t.pumpAndSettle();
      final mill = t.widget<KnittingScreen>(find.byType(KnittingScreen));
      expect(mill.workspace.company, 'Kaveri Loomworks');
      expect(mill.api, same(opened[1]));
      expect(mill.api, isNot(same(generalHub.api)));
      await t.tap(find.text('Invoices').first);
      await t.pumpAndSettle();
      final knittingHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
      expect(knittingHub.company, 'Kaveri Loomworks');
      expect(knittingHub.api, same(mill.api));
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('General ERP'));
      await t.pumpAndSettle();
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Kaveri Loomworks',
      );
      expect(find.text('Knitting workspace'), findsNothing);
      await t.tap(find.text('Kaveri Loomworks').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SimpleDialogOption, 'Meridian Trading'));
      await t.pumpAndSettle();
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Meridian Trading',
      );
      expect(find.byType(KnittingScreen), findsNothing);
      await t.tap(find.text('Invoices').first);
      await t.pumpAndSettle();
      final returnedHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
      expect(returnedHub.company, 'Meridian Trading');
      expect(returnedHub.api, same(opened[2]));
      expect(find.text('Kaveri Loomworks'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable local company leaves the current company and invoices usable',
    (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = _LocalApi('Meridian Trading');
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            openLocal: () async =>
                LocalWorkspace(api, 'Meridian Trading', companies: _companies),
            openLocalCompany: (_) async => throw const ErpException(
              'The selected company is unavailable.',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Meridian Trading').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SimpleDialogOption, 'Kaveri Loomworks'));
      await t.pumpAndSettle();
      expect(find.text('The selected company is unavailable.'), findsOneWidget);
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Meridian Trading',
      );
      expect(find.byType(KnittingScreen), findsNothing);
      await t.tap(find.text('Invoices').first);
      await t.pumpAndSettle();
      expect(t.widget<InvoiceHub>(find.byType(InvoiceHub)).api, same(api));
      expect(
        t.widget<InvoiceHub>(find.byType(InvoiceHub)).company,
        'Meridian Trading',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'configured workspace uses authenticated multi-company access without requiring manager rights',
    (t) async {
      final api = _MultiCompanyApi('Archive One');
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            openLocal: () async => LocalWorkspace(
              api,
              'Archive One',
              workspaceId: 'history-test',
              workspaceLabel: 'Imported test workspace',
              profiles: const [
                {'id': 'history-test', 'label': 'Imported test workspace'},
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.text('Imported history'), findsOneWidget);
      await t.tap(find.text('Archive One').first);
      await t.pumpAndSettle();
      for (final company in ['Archive Two', 'Archive Three', 'Archive Four']) {
        expect(
          find.widgetWithText(SimpleDialogOption, company),
          findsOneWidget,
        );
      }
      expect(find.text('Meridian Trading'), findsNothing);
    },
  );

  testWidgets(
    'configured companies and demo profiles switch without mixing account scope',
    (t) async {
      const profiles = [
        {'id': 'history', 'label': 'Imported test workspace'},
        {'id': 'demo', 'label': 'General demo workspace'},
      ];
      final opened = <ErpApi>[];
      Future<LocalWorkspace> open(String id, String? company) async {
        final name = id == 'demo'
            ? 'Meridian Trading'
            : company ?? 'Archive One';
        final api = id == 'demo' ? _LocalApi(name) : _MultiCompanyApi(name);
        opened.add(api);
        return LocalWorkspace(api, name, workspaceId: id, profiles: profiles);
      }

      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            openLocal: () => open('history', null),
            openLocalProfile: open,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Archive One').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SimpleDialogOption, 'Archive Two'));
      await t.pumpAndSettle();
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Archive Two',
      );
      expect(opened.length, 2);
      await t.tap(find.text('Archive Two').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Switch workspace'));
      await t.pumpAndSettle();
      await t.tap(find.text('General demo workspace'));
      await t.pumpAndSettle();
      expect(
        t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
        'Meridian Trading',
      );
      expect(find.text('Imported history'), findsNothing);
      expect(find.text('Archive Two'), findsNothing);
      expect(opened.length, 3);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'private launcher credentials are unavailable outside macOS',
    () async {
      expect(LocalWorkspace.enabled, isFalse);
      await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
    },
    skip: Platform.isMacOS,
  );

  bool requireMacLauncher() {
    if (Platform.isMacOS) return true;
    markTestSkipped('Private launcher credentials require macOS.');
    return false;
  }

  group('private local company access', () {
    const channel = MethodChannel('org.localerp.workspace/local');
    late Directory support;
    late Map<String, dynamic> saved;
    setUp(() {
      support = Directory.systemTemp.createTempSync('erp-local-company-test-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async =>
                call.method == 'applicationSupport' ? support.path : null,
          );
      saved = {
        'site': 'native-test.localhost',
        'company': 'Meridian Trading',
        'workspaces': [
          {
            'site': 'native-test.localhost',
            'company': 'Meridian Trading',
            'account': 'local-general-owner@workspace.example.invalid',
            'key': 'general-test-key',
            'secret': 'general-test-secret',
          },
          {
            'site': 'native-test.localhost',
            'company': 'Kaveri Loomworks',
            'account': 'local-owner@workspace.example.invalid',
            'key': 'knitting-test-key',
            'secret': 'knitting-test-secret',
          },
        ],
      };
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      support.deleteSync(recursive: true);
    });
    void writeAccess(Map<String, dynamic> data) {
      final file = File('${support.path}/ERP Workspace/local-launch.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(data));
    }

    test(
      'opens a separate configured local profile without trusting file company choices',
      () async {
        if (!requireMacLauncher()) return;
        writeAccess({
          'version': 2,
          'selected_workspace': 'history-test',
          'workspaces': [
            {
              'id': 'history-test',
              'label': 'Imported test workspace',
              'origin': 'http://127.0.0.1:8082',
              'site': 'history-test.localhost',
              'company': 'Archive Company One',
              'account': 'history-owner@example.invalid',
              'key': 'history-test-key',
              'secret': 'history-test-secret',
              'companies': [
                {'name': 'Untrusted company'},
              ],
            },
          ],
        });
        final local = await LocalWorkspace.open();
        addTearDown(local.api.close);
        expect(local.api.baseUri, Uri.parse('http://127.0.0.1:8082'));
        expect(local.api.account, 'history-owner@example.invalid');
        expect(local.company, 'Archive Company One');
        expect(local.companies, isEmpty);
        expect(local.profiles, [
          {'id': 'history-test', 'label': 'Imported test workspace'},
        ]);
      },
    );

    test(
      'configured credentials reject remote origins and duplicate workspace ids',
      () async {
        Map<String, dynamic> profile() => {
          'id': 'history-test',
          'label': 'Imported test workspace',
          'origin': 'https://example.invalid',
          'site': 'history-test.localhost',
          'company': 'Archive One',
          'account': 'history-owner@example.invalid',
          'key': 'history-test-key',
          'secret': 'history-test-secret',
        };
        writeAccess({
          'version': 2,
          'selected_workspace': 'history-test',
          'workspaces': [profile()],
        });
        await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
        final local = profile()..['origin'] = 'http://127.0.0.1:8082';
        writeAccess({
          'version': 2,
          'selected_workspace': 'history-test',
          'workspaces': [local, local],
        });
        await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
      },
    );

    test(
      'opens the selected company with its own account and no secrets in picker data',
      () async {
        if (!requireMacLauncher()) return;
        writeAccess(saved);
        final general = await LocalWorkspace.open();
        addTearDown(general.api.close);
        expect(general.company, 'Meridian Trading');
        expect(
          general.api.account,
          'local-general-owner@workspace.example.invalid',
        );
        expect(general.companies, _companies);
        final knitting = await LocalWorkspace.open(company: 'Kaveri Loomworks');
        addTearDown(knitting.api.close);
        expect(knitting.company, 'Kaveri Loomworks');
        expect(knitting.api.account, 'local-owner@workspace.example.invalid');
        expect(knitting.companies, _companies);
      },
    );

    test('rejects an account belonging to a different company', () async {
      (saved['workspaces'] as List).first['account'] =
          'local-owner@workspace.example.invalid';
      writeAccess(saved);
      await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
    });

    test(
      'rejects a foreign site or duplicate company in the selector',
      () async {
        final entries = saved['workspaces'] as List;
        entries.last['site'] = 'customer.example.invalid';
        writeAccess(saved);
        await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
        entries[1] = Map<String, String>.from(entries.first as Map);
        writeAccess(saved);
        await expectLater(LocalWorkspace.open(), throwsA(isA<ErpException>()));
      },
    );

    test('rejects companies that have not been provisioned locally', () async {
      writeAccess(saved);
      await expectLater(
        LocalWorkspace.open(company: 'Unlisted company'),
        throwsA(isA<ErpException>()),
      );
    });

    test('keeps an existing single company credential usable', () async {
      if (!requireMacLauncher()) return;
      writeAccess(
        Map<String, dynamic>.from((saved['workspaces'] as List).last as Map),
      );
      final local = await LocalWorkspace.open();
      addTearDown(local.api.close);
      expect(local.company, 'Kaveri Loomworks');
      expect(local.api.account, 'local-owner@workspace.example.invalid');
      expect(local.companies, [_companies.last]);
    });
  });

  test('local credential refuses all other origins and ports', () {
    for (final uri in [
      'https://example.invalid',
      'http://localhost:8081',
      'http://127.0.0.1:8080',
    ]) {
      final api = ErpApi(Uri.parse(uri));
      addTearDown(api.close);
      expect(
        () => api.useLocalWorkspace(
          'local-key-0123456789',
          'local-secret-0123456789',
        ),
        throwsA(isA<ErpException>()),
      );
    }
  });
}
