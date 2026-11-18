import 'package:erp_client/local_workspace.dart';

import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/features/workspace/data/erp_workspace_repository.dart';
import 'package:erp_client/features/workspace/data/workspace_repository.dart';
import 'package:erp_client/features/workspace/presentation/workspace_view_model.dart';
import 'package:erp_client/features/workspace/presentation/workspace_picker_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext _context(String company) => WorkspaceContext.fromJson({
  'company': company,
  'companies': [
    for (final name in {'A', 'B', company}) {'name': name},
  ],
  'can_manage_team': true,
});

class _Repository implements WorkspaceRepository {
  Object token = Object();
  @override
  Object get identity => token;
  Object scopeToken = Object();
  @override
  Object? get accessScope => scopeToken;
  final reads = <(String?, Completer<WorkspaceContext>)>[];
  final selections = <(String, Completer<WorkspaceContext>)>[];
  @override
  Future<WorkspaceContext> load({String? company}) {
    final next = Completer<WorkspaceContext>();
    reads.add((company, next));
    return next.future;
  }

  @override
  Future<WorkspaceContext> current(String? company) => load(company: company);
  @override
  Future<WorkspaceContext> select(String company) {
    final next = Completer<WorkspaceContext>();
    selections.add((company, next));
    return next.future;
  }
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final reads = <String?>[];
  final pending = Completer<WorkspaceContext>();
  bool denied = false;
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) {
    reads.add(company);
    if (denied && company != null) {
      return Future.error(
        const ErpException('No access', permissionDenied: true),
      );
    }
    return pending.future;
  }
}

class _LocalFallbackApi extends ErpApi {
  _LocalFallbackApi() : super(Uri.parse('http://127.0.0.1:8081'));
  bool revoked = false;
  final reads = <String?>[];
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async {
    reads.add(company);
    if (revoked && company == 'A') {
      throw const ErpException('Revoked', permissionDenied: true);
    }
    return WorkspaceContext.fromJson({
      'company': revoked ? 'B' : 'A',
      'companies': [
        if (!revoked) {'name': 'A'},
        {'name': 'B'},
      ],
      'can_manage_team': false,
    });
  }
}

void main() {
  test('older context reads cannot replace the latest company', () async {
    final repository = _Repository();
    final model = WorkspaceViewModel(repository);
    final old = model.load(company: 'A'), next = model.load(company: 'B');
    repository.reads[1].$2.complete(_context('B'));
    await next;
    repository.reads[0].$2.complete(_context('A'));
    await old;
    expect(model.context!.company, 'B');
  });
  test('a disposed workspace cannot publish a delayed context', () async {
    final repository = _Repository();
    final model = WorkspaceViewModel(repository);
    final loading = model.load();
    model.dispose();
    repository.reads.single.$2.complete(_context('A'));
    await loading;
    expect(model.context, isNull);
  });
  test(
    'explicit company selection stays serialized through a concurrent refresh',
    () async {
      final repository = _Repository();
      final model = WorkspaceViewModel(repository);
      final initial = model.load(company: 'A');
      repository.reads.single.$2.complete(_context('A'));
      await initial;
      final selecting = model.select('B');
      final reading = model.load(company: 'A');
      repository.reads.last.$2.complete(_context('A'));
      await reading;
      expect(model.selecting, isTrue);
      expect(await model.select('A'), isNull);
      expect(repository.selections, hasLength(1));
      repository.selections.single.$2.complete(_context('B'));
      await selecting;
      expect(model.context!.company, 'B');
      expect(model.selecting, isFalse);
    },
  );
  test('the current company is not written again as a preference', () async {
    final repository = _Repository();
    final model = WorkspaceViewModel(repository);
    final loading = model.load();
    repository.reads.single.$2.complete(_context('A'));
    await loading;
    expect(await model.select('A'), isNull);
    expect(repository.selections, isEmpty);
  });
  test(
    'the workspace repository rejects a changed account after a delayed read',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpWorkspaceRepository(api);
      final loading = repository.load(company: 'A');
      final rejected = expectLater(loading, throwsA(isA<ErpException>()));
      api.account = 'replacement@example.invalid';
      api.pending.complete(_context('A'));
      await rejected;
    },
  );
  test('a context refresh may publish its own new access revision', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpWorkspaceRepository(api);
    final loading = repository.load(company: 'A');
    api.accessRevision++;
    api.pending.complete(_context('A'));
    expect((await loading).company, 'A');
  });
  test(
    'permission loss falls back only for an explicit current-context refresh',
    () async {
      final api = _Api()..denied = true;
      addTearDown(api.close);
      final repository = ErpWorkspaceRepository(api);
      await expectLater(
        repository.load(company: 'A'),
        throwsA(isA<ErpException>()),
      );
      final loading = repository.current('A');
      api.pending.complete(_context('B'));
      expect((await loading).company, 'B');
      expect(api.reads, ['A', 'A', null]);
    },
  );
  test(
    'the repository rejects a response for an unrequested company',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpWorkspaceRepository(api);
      final loading = repository.load(company: 'A');
      final rejected = expectLater(loading, throwsA(isA<ErpException>()));
      api.pending.complete(_context('B'));
      await rejected;
    },
  );
  test(
    'picker search preserves record descriptions and overview filtering',
    () {
      final model = WorkspacePickerViewModel(ErpModule.values);
      model.search('  BUSINESS OVERVIEW ');
      expect(model.showOverview, isTrue);
      model.search('Sales Invoice');
      expect(
        model.modules.map((module) => module.doctype),
        contains('Sales Invoice'),
      );
      model.search('not-a-record');
      expect(model.modules, isEmpty);
      expect(model.showOverview, isFalse);
    },
  );
  test(
    'current-context fallback never changes accounts during its request',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpWorkspaceRepository(api);
      final loading = repository.current('A');
      final rejected = expectLater(loading, throwsA(isA<ErpException>()));
      api.account = 'replacement@example.invalid';
      api.pending.complete(_context('A'));
      await rejected;
      expect(api.reads, ['A']);
    },
  );
  test(
    'an invalid company response is not treated as permission-loss fallback',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpWorkspaceRepository(api);
      final loading = repository.current('A');
      final rejected = expectLater(loading, throwsA(isA<ErpException>()));
      api.pending.complete(_context('B'));
      await rejected;
      expect(api.reads, ['A']);
    },
  );
  test('review regression: configured local profiles accept authorized fallback after opening', () async {
    final api = _LocalFallbackApi();
    addTearDown(api.close);
    final local = LocalWorkspace(api, 'A', workspaceId: 'synthetic-multi');
    final repository = ErpWorkspaceRepository(api, local: local);
    expect((await repository.load(company: 'A')).company, 'A');
    api.revoked = true;
    expect((await repository.current('A')).company, 'B');
    expect(api.reads, ['A', 'A', null]);
  });
}
