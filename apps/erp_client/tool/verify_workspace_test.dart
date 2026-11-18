// Connected contract check; only the isolated synthetic native-test site.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/workspace/data/erp_workspace_repository.dart';
import 'package:erp_client/features/workspace/presentation/workspace_view_model.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  test('synthetic workspace context and company selection preserve scope', () async {
    final origin = Uri.parse(
      Platform.environment['ERP_URL'] ?? 'http://127.0.0.1:8081',
    );
    if (!{'localhost', '127.0.0.1'}.contains(origin.host) ||
        origin.port != 8081 ||
        origin.scheme != 'http' ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !{'', '/'}.contains(origin.path)) {
      throw StateError('Require the isolated local test origin.');
    }
    final username = Platform.environment['ERP_USERNAME'];
    final password = Platform.environment['ERP_PASSWORD'];
    if (username == null || password == null) {
      throw StateError('Require synthetic verification credentials.');
    }
    final api = ErpApi(origin);
    WorkspaceViewModel? model;
    String? previousCompany;
    var changedPreference = false;
    try {
      await api.login(username, password);
      final catalog = await api.nativeCatalog();
      expect(catalog.site, 'native-test.localhost');
      final initial = await api.workspaceContext();
      previousCompany = initial.company;
      expect(
        previousCompany,
        isNotNull,
        reason: 'Require a preference that can be restored before changing it.',
      );
      const first = 'ERP Native Verification', second = 'Meridian Trading';
      expect(
        initial.companies.map((row) => row['name']),
        containsAll([first, second]),
      );
      final repository = ErpWorkspaceRepository(
        api,
        local: LocalWorkspace(
          api,
          first,
          workspaceId: 'architecture-synthetic',
        ),
        requestedCompany: first,
      );
      model = WorkspaceViewModel(repository);
      expect((await model.load(company: first))!.company, first);
      expect((await model.current(first))!.company, first);
      expect(await model.select(first), isNull);
      // Set before the request so restoration also runs after a lost response.
      changedPreference = true;
      expect((await model.select(second))!.company, second);
      expect(model.context!.company, second);
      expect((await model.current(second))!.company, second);
      expect((await api.workspaceContext()).company, second);
      stdout.writeln(
        jsonEncode({
          'site': catalog.site,
          'contextAndSelection': 'passed',
          'createdBusinessRecords': 0,
        }),
      );
    } finally {
      model?.dispose();
      try {
        if (changedPreference && previousCompany != null) {
          expect(
            (await api.selectCompany(previousCompany)).company,
            previousCompany,
          );
        }
        await api.signOut();
      } finally {
        api.close();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
