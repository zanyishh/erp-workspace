import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';

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

  test('authenticated reads send the login session and scoped query', () async {
    final seen = <HttpRequest>[];
    String? sentSession;
    dynamic sentFilters;
    server.listen((request) async {
      seen.add(request);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/login')) {
        request.response.cookies.add(Cookie('sid', 'test-session'));
        request.response.write(
          jsonEncode({'message': 'Logged In', 'full_name': 'Evaluator'}),
        );
      } else {
        sentSession = request.cookies.singleWhere((c) => c.name == 'sid').value;
        sentFilters = jsonDecode(request.uri.queryParameters['filters']!);
        request.response.write(
          jsonEncode({
            'message': [
              {
                'name': 'SO-1001',
                'customer_name': 'One Shop',
                'status': 'Draft',
                'grand_total': 1200,
                'currency': 'INR',
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    await api.login('Administrator', 'test-only');
    final rows = await api.records(
      ErpModule.selling,
      company: 'ERP Evaluation',
      period: ReportingPeriod.month,
      now: DateTime(2026, 11, 12),
    );
    expect(sentSession, 'test-session');
    expect(sentFilters, contains(equals(['company', '=', 'ERP Evaluation'])));
    expect(rows.single.title, 'One Shop');
    expect(rows.single.name, 'SO-1001');
    expect(seen.length, 2);
  });

  test(
    'expired sessions produce authentication errors instead of empty data',
    () async {
      server.listen((r) async {
        r.response.statusCode = 401;
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"message":"Session expired"}');
        await r.response.close();
      });
      await expectLater(
        api.records(ErpModule.stock, company: 'ERP Evaluation'),
        throwsA(
          isA<ErpException>().having((e) => e.sessionExpired, 'expired', true),
        ),
      );
    },
  );

  test(
    'malformed record responses are errors rather than invented zero rows',
    () async {
      server.listen((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"message":"unexpected"}');
        await r.response.close();
      });
      await expectLater(
        api.records(ErpModule.stock, company: 'ERP Evaluation'),
        throwsA(isA<ErpException>()),
      );
    },
  );
  test(
    'dashboard totals use company currency rather than mixing invoice currencies',
    () async {
      var unpaidFilterSeen = false;
      server.listen((r) async {
        final q = r.uri.queryParameters;
        final type = q['doctype'];
        Object response;
        if (r.uri.path.endsWith('get_count')) {
          final filters = jsonDecode(q['filters']!);
          if (type == 'Sales Invoice' &&
              filters.any((f) => f[0] == 'outstanding_amount')) {
            unpaidFilterSeen = true;
          }
          response = 1;
        } else if (type == 'Company') {
          response = [
            {'name': 'ERP Evaluation', 'default_currency': 'INR'},
          ];
        } else {
          final fields = jsonDecode(q['fields']!);
          if (fields.any((f) => f is Map && f['as'] == 'billed')) {
            response = [
              {
                'billed':
                    fields.any(
                      (f) => f is Map && f['SUM'] == 'base_grand_total',
                    )
                    ? 8500
                    : 100,
                'unpaid': 0,
              },
            ];
          } else {
            response = <Object>[];
          }
        }
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({'message': response}));
        await r.response.close();
      });
      final data = await api.snapshot(ReportingPeriod.month);
      expect(data.currency, 'INR');
      expect(data.billed, 8500);
      expect(unpaidFilterSeen, isTrue);
    },
  );
  test(
    'sign-out revokes the server session with POST and drops its cookie',
    () async {
      final methods = <String>[];
      var cookieAfterLogout = '';
      server.listen((r) async {
        methods.add(r.method);
        r.response.headers.contentType = ContentType.json;
        if (r.uri.path.endsWith('/login')) {
          r.response.cookies.add(Cookie('sid', 'test-session'));
          r.response.write('{"message":"Logged In"}');
        } else if (r.uri.path.endsWith('/logout')) {
          if (r.method != 'POST') r.response.statusCode = 403;
          r.response.write('{"message":"ok"}');
        } else {
          cookieAfterLogout = r.headers.value(HttpHeaders.cookieHeader) ?? '';
          r.response.write('{"message":[]}');
        }
        await r.response.close();
      });
      await api.login('Administrator', 'test-only');
      await api.signOut();
      await api.records(ErpModule.stock, company: 'ERP Evaluation');
      expect(methods, ['POST', 'POST', 'GET']);
      expect(cookieAfterLogout, isEmpty);
    },
  );

  for (final deniedType in ['Work Order', 'Sales Invoice']) {
    test('denied $deniedType does not block authorized modules', () async {
      server.listen((r) async {
        final q = r.uri.queryParameters;
        final type = q['doctype'];
        r.response.headers.contentType = ContentType.json;
        if (type == deniedType) {
          r.response.statusCode = 403;
          r.response.write('{"exc_type":"PermissionError"}');
        } else {
          final fields = jsonDecode(q['fields'] ?? '[]') as List;
          final Object response = type == 'Company'
              ? [
                  {'name': 'Allowed Company', 'default_currency': 'INR'},
                ]
              : r.uri.path.endsWith('get_count')
              ? 2
              : fields.any((f) => f is Map && f['as'] == 'billed')
              ? [
                  {'billed': 500},
                ]
              : <Object>[];
          r.response.write(jsonEncode({'message': response}));
        }
        await r.response.close();
      });
      final data = await api.snapshot(ReportingPeriod.month);
      expect(data.count(ErpModule.stock), 2);
      expect(
        data.count(ErpModule.manufacturing),
        deniedType == 'Work Order' ? isNull : 2,
      );
      expect(data.billed, deniedType == 'Sales Invoice' ? isNull : 500);
      expect(
        data.count(ErpModule.accounts),
        deniedType == 'Sales Invoice' ? isNull : 2,
      );
    });
  }

  test('invalid amounts fail at the API boundary before rendering', () async {
    server.listen((r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'message': [
            {'name': 'SO-1', 'grand_total': 'not-a-number'},
          ],
        }),
      );
      await r.response.close();
    });
    await expectLater(
      api.records(ErpModule.selling, company: 'Example'),
      throwsA(isA<ErpException>()),
    );
  });
}
