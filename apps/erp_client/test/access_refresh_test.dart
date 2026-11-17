import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';

void main() {
  test(
    'explicit selected company is queried directly and never falls back',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      server.listen((r) async {
        final q = r.uri.queryParameters;
        Object result;
        if (q['doctype'] == 'Company') {
          final filters = q['filters'] ?? '';
          result = filters.contains('Company 51')
              ? [
                  {'name': 'Company 51', 'default_currency': 'EUR'},
                ]
              : [
                  {'name': 'Company 1', 'default_currency': 'INR'},
                ];
        } else if (r.uri.path.endsWith('get_count')) {
          result = 0;
        } else {
          final fields = jsonDecode(q['fields'] ?? '[]') as List;
          result = fields.any((v) => v is Map && v['as'] == 'billed')
              ? [
                  {'billed': 0},
                ]
              : [];
        }
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({'message': result}));
        await r.response.close();
      });
      final result = await api.snapshot(
        ReportingPeriod.month,
        selectedCompany: 'Company 51',
      );
      expect(result.company, 'Company 51');
      expect(result.currency, 'EUR');
    },
  );

  test('session recovery quarantines cached access and publishes fresh permissions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
    var logins = 0;
    server.listen((r) async {
      r.response.headers.contentType = ContentType.json;
      if (r.uri.path.endsWith('/login')) {
        logins++;
        r.response.cookies.add(Cookie('sid', 'session-$logins'));
        r.response.write('{"message":"Logged In"}');
      } else if (r.uri.path.endsWith('workspace.context')) {
        r.response.write(
          jsonEncode({
            'message': {
              'company': 'Demo',
              'knitting_enabled': true,
              'access_fingerprint': 'roles-$logins',
              'capabilities': logins == 1
                  ? ['jobs', 'reports', 'financial_read']
                  : ['jobs'],
            },
          }),
        );
      } else {
        r.response.statusCode = 401;
        r.response.write('{"exc_type":"SessionExpired"}');
      }
      await r.response.close();
    });
    await api.login('staff', 'synthetic');
    await api.workspaceContext(company: 'Demo');
    final readiness = <bool>[];
    api.addAccessListener(() => readiness.add(api.accessReady));
    api.onSessionExpired = () async {
      await api.login('staff', 'synthetic');
      return true;
    };
    await expectLater(
      api.knittingSnapshot('Demo'),
      throwsA(isA<ErpException>()),
    );
    expect(readiness, containsAllInOrder([false, true]));
    expect(api.accessRevision, 1);
    expect(api.contextFor('Demo')!.allows('financial_read'), isFalse);
  });
}
