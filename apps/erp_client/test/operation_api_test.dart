import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/workspace_context.dart';

void main() {
  late HttpServer server;
  late ErpApi api;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });

  test(
    'recovery is scoped to an advertised workspace and revoked with access',
    () {
      expect(api.supportsOperationRecovery('One'), isFalse);
      api.publishContext(WorkspaceContext.fromJson({'company': 'One'}));
      expect(api.supportsOperationRecovery('One'), isFalse);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'One',
          'operation_recovery_version': 1,
        }),
      );
      expect(api.supportsOperationRecovery('One'), isTrue);
      expect(api.supportsOperationRecovery('Two'), isFalse);
      api.accessReady = false;
      expect(api.supportsOperationRecovery('One'), isFalse);
    },
  );

  test(
    'reference APIs use scoped POSTs without sending draft financial values',
    () async {
      final sent = <(String, Map<String, String>)>[];
      server.listen((request) async {
        expect(request.method, 'POST');
        final body = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        sent.add((request.uri.path.split('.').last, body));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': request.uri.path.endsWith('pending_operations')
                ? {'rows': [], 'has_more': false}
                : {'request_id': 'native-operation-1', 'state': 'prepared'},
          }),
        );
        await request.response.close();
      });
      await api.beginOperation(
        'One',
        'native_save',
        'native-operation-1',
        doctype: 'Sales Invoice',
        name: 'INV-1',
        action: 'Save',
      );
      await api.pendingOperations('One', start: 50);
      await api.operationStatus('One', 'native-operation-1');
      await api.closeOperation('One', 'native-operation-1');
      await api.acknowledgeOperation('One', 'native-operation-1');
      expect(sent.map((row) => row.$1), [
        'begin_operation',
        'pending_operations',
        'operation_status',
        'close_operation',
        'acknowledge_operation',
      ]);
      expect(sent.first.$2, {
        'company': 'One',
        'kind': 'native_save',
        'request_id': 'native-operation-1',
        'doctype': 'Sales Invoice',
        'name': 'INV-1',
        'action': 'Save',
      });
      expect(sent[1].$2, {'company': 'One', 'start': '50'});
      expect(sent.last.$2, {
        'company': 'One',
        'request_id': 'native-operation-1',
      });
    },
  );

  test(
    'native writes carry the same operation reference without implicit replay',
    () async {
      final sent = <Map<String, String>>[];
      server.listen((request) async {
        sent.add(Uri.splitQueryString(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {
              'doc': {'doctype': 'Example', 'name': 'ONE'},
              'permissions': {},
            },
          }),
        );
        await request.response.close();
      });
      final schema = NativeSchema.fromJson({
        'doctype': 'Example',
        'fields': [],
      });
      await api.saveNative(
        schema,
        {'doctype': 'Example', '__islocal': 1},
        requestId: 'native-operation-1',
        company: 'One',
      );
      await api.transitionNative(
        'Example',
        'ONE',
        'Approve',
        modified: 'version',
        requestId: 'native-operation-2',
        company: 'One',
      );
      expect(sent, hasLength(2));
      expect(sent[0]['request_id'], 'native-operation-1');
      expect(sent[1]['request_id'], 'native-operation-2');
      expect(sent.every((body) => body['company'] == 'One'), isTrue);
    },
  );
}
