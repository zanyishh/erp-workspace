import 'dart:io';

import 'package:erp_client/core/models/workspace_edition.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/workspace/data/erp_workspace_repository.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompanyApi extends ErpApi {
  _CompanyApi() : super(Uri.parse('http://localhost:8081'));
  var mill = false;
  var switched = false;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      WorkspaceContext.fromJson({
        'company': company ?? (mill ? 'Mill' : 'General'),
        'knitting_enabled': mill,
        'knitting_only': mill,
      });
  @override
  Future<WorkspaceContext> selectCompany(String company) {
    switched = true;
    return workspaceContext(company: company);
  }
}

class _OfflineClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw const SocketException('Connection refused');
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a stopped local knitting service identifies its local address',
    () async {
      await HttpOverrides.runZoned(() async {
        final api = ErpApi(Uri.parse('http://127.0.0.1:8082'));
        addTearDown(api.close);
        await expectLater(
          api.login('test', 'test'),
          throwsA(
            isA<ErpException>().having(
              (e) => e.message,
              'message',
              contains('local ERPNext service at 127.0.0.1:8082'),
            ),
          ),
        );
      }, createHttpClient: (_) => _OfflineClient());
    },
  );
  test(
    'distribution accepts its workspace and preserves customer boundaries',
    () async {
      final api = _CompanyApi();
      addTearDown(api.close);
      final repo = ErpWorkspaceRepository(api);
      if (knittingCustomerBuild) {
        await expectLater(repo.load(), throwsA(isA<ErpException>()));
      } else {
        expect((await repo.load()).company, 'General');
      }
      api.mill = true;
      expect((await repo.load()).company, 'Mill');
      if (knittingCustomerBuild) {
        await expectLater(repo.select('Other'), throwsA(isA<ErpException>()));
        expect(api.switched, isFalse);
        api.mill = false;
        await expectLater(repo.current('Mill'), throwsA(isA<ErpException>()));
      }
    },
  );
  testWidgets('entry screen identifies the installed product', (t) async {
    await t.pumpWidget(const MaterialApp(home: WorkspaceShell()));
    expect(
      find.text(knittingCustomerBuild ? 'Knitting Workspace' : 'ERP Workspace'),
      findsOneWidget,
    );
    expect(
      find.text('Create a company'),
      knittingCustomerBuild ? findsNothing : findsOneWidget,
    );
  });
}
