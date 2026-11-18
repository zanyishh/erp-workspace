import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/operations/data/erp_operation_repository.dart';
import 'package:erp_client/features/operations/data/operation_repository.dart';
import 'package:erp_client/features/operations/models/operation_reference.dart';
import 'package:erp_client/features/operations/presentation/pending_operations_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({
  String id = 'request-1',
  String company = 'Synthetic',
  String state = 'prepared',
  Map<String, dynamic>? result,
}) => {
  'request_id': id,
  'company': company,
  'kind': 'invoice',
  'state': state,
  'action': 'Save',
  'creation': '2026-11-16 12:00:00',
  'result': ?result,
};
OperationReference _reference({String state = 'prepared'}) =>
    OperationReference.fromJson(_json(state: state));

class _Repository implements OperationRepository {
  Object? token = Object();
  @override
  Object? get scope => token;
  final starts = <int>[];
  final commands = <(String, String)>[];
  final checks = <Completer<OperationReference>>[];
  final closes = <Completer<OperationReference>>[];
  Future<OperationPage> Function(int)? read;
  Object? acknowledgeError;
  @override
  Future<OperationPage> load({int start = 0}) async {
    starts.add(start);
    return read?.call(start) ??
        OperationPage(rows: [_reference()], hasMore: false);
  }

  @override
  Future<OperationReference> status(String id) {
    commands.add(('status', id));
    final result = Completer<OperationReference>();
    checks.add(result);
    return result.future;
  }

  @override
  Future<OperationReference> closeUnposted(String id) {
    commands.add(('close', id));
    final result = Completer<OperationReference>();
    closes.add(result);
    return result.future;
  }

  @override
  Future<void> acknowledge(String id) async {
    commands.add(('acknowledge', id));
    if (acknowledgeError case final error?) throw error;
  }
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final response = Completer<Map<String, dynamic>>();
  final starts = <(String, int)>[];
  @override
  Future<Map<String, dynamic>> pendingOperations(
    String company, {
    int start = 0,
  }) {
    starts.add((company, start));
    return response.future;
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String id,
  ) async => _json(id: 'other');
}

void main() {
  test('loading recovery references never sends a status, close or acknowledgment command', () async {
    final repository = _Repository();
    final model = PendingOperationsViewModel(repository);
    await model.load();
    expect(model.rows.single.requestId, 'request-1');
    expect(repository.commands, isEmpty);
    expect(() => model.rows.clear(), throwsUnsupportedError);
  });

  test('filtered empty pages advance the raw ledger offset by 50', () async {
    final repository = _Repository();
    repository.read = (start) async =>
        OperationPage(rows: [], hasMore: start == 0);
    final model = PendingOperationsViewModel(repository);
    await model.load();
    await model.nextPage();
    expect(repository.starts, [0, 50]);
    expect(model.page, 1);
  });

  test(
    'refresh during a status check retires busy state and keeps the newer read',
    () async {
      final repository = _Repository();
      final model = PendingOperationsViewModel(repository);
      await model.load();
      final checking = model.checkStatus('request-1');
      expect(model.isWorking('request-1'), isTrue);
      await model.load();
      repository.checks.single.complete(_reference(state: 'closed'));
      await checking;
      expect(model.isWorking('request-1'), isFalse);
      expect(model.rows.single.state, 'prepared');
    },
  );

  test(
    'closing is serialized and a completion that wins the race stays completed',
    () async {
      final repository = _Repository();
      final model = PendingOperationsViewModel(repository);
      await model.load();
      final first = model.closeUnposted('request-1');
      await model.closeUnposted('request-1');
      expect(repository.commands, [('close', 'request-1')]);
      repository.closes.single.complete(_reference(state: 'completed'));
      await first;
      expect(model.rows.single.state, 'completed');
      expect(model.isWorking('request-1'), isFalse);
    },
  );

  test('prepared operations cannot be dismissed and failed acknowledgment keeps the reference', () async {
    final repository = _Repository();
    final model = PendingOperationsViewModel(repository);
    await model.load();
    await model.dismiss('request-1');
    expect(repository.commands, isEmpty);
    repository.read = (_) async =>
        OperationPage(rows: [_reference(state: 'closed')], hasMore: false);
    await model.load();
    repository.acknowledgeError = const ErpException('Offline');
    await model.dismiss('request-1');
    expect(model.rows.single.requestId, 'request-1');
    expect(model.error, contains('Offline'));
    repository.acknowledgeError = null;
    await model.dismiss('request-1');
    expect(model.rows, isEmpty);
  });

  test('cached references cannot send commands after their account or access scope changes', () async {
    final repository = _Repository();
    final model = PendingOperationsViewModel(repository);
    await model.load();
    repository.token = Object();
    await model.closeUnposted('request-1');
    expect(repository.commands, isEmpty);
    expect(model.rows, isEmpty);
    expect(model.error, isNotNull);
  });

  test('an old scope completion cannot clear a new scope busy token', () async {
    final repository = _Repository();
    final model = PendingOperationsViewModel(repository);
    await model.load();
    final old = model.checkStatus('request-1');
    repository.token = Object();
    await model.load();
    final current = model.checkStatus('request-1');
    repository.checks[0].complete(_reference(state: 'closed'));
    await old;
    expect(model.isWorking('request-1'), isTrue);
    repository.checks[1].complete(_reference(state: 'completed'));
    await current;
    expect(model.isWorking('request-1'), isFalse);
    expect(model.rows.single.state, 'completed');
  });

  test('scope loss during a status check removes cached references', () async {
    final repository = _Repository();
    final model = PendingOperationsViewModel(repository);
    await model.load();
    final checking = model.checkStatus('request-1');
    repository.token = Object();
    repository.checks.single.completeError(
      const ErpException('Access changed', permissionDenied: true),
    );
    await checking;
    expect(model.rows, isEmpty);
    expect(model.error, isNotNull);
  });

  test(
    'disposing the view model prevents a pending page from being published',
    () async {
      final repository = _Repository();
      final page = Completer<OperationPage>();
      repository.read = (_) => page.future;
      final model = PendingOperationsViewModel(repository);
      final loading = model.load();
      model.dispose();
      page.complete(OperationPage(rows: [_reference()], hasMore: false));
      await loading;
      expect(model.rows, isEmpty);
    },
  );

  test(
    'repository scopes raw offsets and exposes immutable receipt values',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpOperationRepository(api: api, company: 'Synthetic');
      final loading = repository.load(start: 50);
      final row = _json(result: {'name': 'SINV-1'});
      final rows = [row];
      api.response.complete({'rows': rows, 'has_more': false});
      final page = await loading;
      rows.clear();
      (row['result'] as Map)['name'] = 'MUTATED';
      expect(api.starts, [('Synthetic', 50)]);
      expect(page.rows.single.result.name, 'SINV-1');
      expect(() => page.rows.clear(), throwsUnsupportedError);
    },
  );

  test(
    'repository rejects a response belonging to another operation reference',
    () async {
      final api = _Api();
      addTearDown(api.close);
      final repository = ErpOperationRepository(api: api, company: 'Synthetic');
      await expectLater(
        repository.status('request-1'),
        throwsA(isA<ErpException>()),
      );
    },
  );

  test('repository sends no read while access is quarantined', () async {
    final api = _Api();
    addTearDown(api.close);
    api.accessReady = false;
    final repository = ErpOperationRepository(api: api, company: 'Synthetic');
    expect(repository.scope, isNull);
    await expectLater(repository.load(), throwsA(isA<ErpException>()));
    expect(api.starts, isEmpty);
  });
}
