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

  test(
    'service origin uses the build setting or local development default',
    () {
      const configured = String.fromEnvironment('ERP_SERVER');
      final expected = configured.isNotEmpty
          ? configured
          : Platform.isAndroid
          ? 'http://10.0.2.2:8081'
          : 'http://localhost:8081';
      expect(ErpApi.serviceOrigin, Uri.parse(expected));
      expect(
        () => ErpApi.validateServer(Uri.parse('http://workspace.example.com')),
        throwsA(isA<ErpException>()),
      );
      expect(
        () => ErpApi.validateServer(
          Uri.parse('https://user@workspace.example.com/path'),
        ),
        throwsA(isA<ErpException>()),
      );
    },
  );

  for (final mode in ['debug', 'profile', 'release']) {
    for (final android in [true, false]) {
      test('service origin policy for Android=$android in $mode', () {
        Uri validate(String value) => validateServiceOrigin(
          Uri.parse(value),
          isAndroid: android,
          isRelease: mode == 'release',
          isProfile: mode == 'profile',
        );
        for (final host in ['localhost', '127.0.0.1', '[::1]', '10.0.2.2']) {
          final local = 'http://$host:8081';
          if (android && mode != 'debug') {
            expect(
              () => validate(local),
              throwsA(
                isA<ErpException>().having(
                  (error) => error.message,
                  'configuration instructions',
                  contains('HTTPS'),
                ),
              ),
            );
          } else {
            expect(validate(local), Uri.parse(local));
          }
        }
        expect(
          validate('https://workspace.example.com/'),
          Uri.parse('https://workspace.example.com'),
        );
        for (final invalid in [
          'http://workspace.example.com',
          'https://user@workspace.example.com/',
          'https://workspace.example.com/private',
          'https://workspace.example.com/?secret=value',
          'https://workspace.example.com/#fragment',
        ]) {
          expect(() => validate(invalid), throwsA(isA<ErpException>()));
        }
      });
    }
  }

  test('unpaid invoice drilldown applies the posted balance and company filters on every page', () async {
    final requests = <Map<String, String>>[];
    server.listen((r) async {
      requests.add(r.uri.queryParameters);
      r.response.headers.contentType = ContentType.json;
      r.response.write('{"message":[]}');
      await r.response.close();
    });
    await api.records(
      ErpModule.accounts,
      company: 'Pilot mill',
      unpaidOnly: true,
      start: 50,
      query: 'Clerk',
    );
    await api.records(ErpModule.accounts, company: 'Pilot mill');
    final filtered = jsonDecode(requests.first['filters']!);
    expect(filtered, contains(equals(['company', '=', 'Pilot mill'])));
    expect(filtered, contains(equals(['docstatus', '=', 1])));
    expect(filtered, contains(equals(['outstanding_amount', '>', 0])));
    expect(requests.first['limit_start'], '50');
    expect(requests.last['filters'], isNot(contains('outstanding_amount')));
  });

  test('rejected credentials tell a signed-out user how to retry', () async {
    server.listen((r) async {
      r.response.statusCode = 401;
      r.response.headers.contentType = ContentType.json;
      r.response.write('{"exc_type":"AuthenticationError"}');
      await r.response.close();
    });
    await expectLater(
      api.login('staff', 'synthetic'),
      throwsA(
        isA<ErpException>()
            .having((e) => e.sessionExpired, 'expired', false)
            .having(
              (e) => e.message,
              'message',
              contains('username and password'),
            ),
      ),
    );
  });

  for (final entry in {
    'Password Reset': 'reset link',
    'No App': 'website account',
  }.entries) {
    test('sign-in gives the ERPNext next step for ${entry.key}', () async {
      server.listen((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({'message': entry.key}));
        await r.response.close();
      });
      await expectLater(
        api.login('staff', 'synthetic'),
        throwsA(
          isA<ErpException>().having(
            (e) => e.message,
            'instructions',
            contains(entry.value),
          ),
        ),
      );
    });
  }

  test('verification uses the same temporary ID, preserves a leading zero, and only accepts a real session', () async {
    final requests = <Map<String, String>>[];
    server.listen((r) async {
      final values = Uri.splitQueryString(await utf8.decoder.bind(r).join());
      requests.add(values);
      r.response.headers.contentType = ContentType.json;
      if (values['usr'] != null) {
        r.response.write(
          jsonEncode({
            'verification': {
              'method': 'Email',
              'setup': true,
              'prompt': 'Check your registered email.',
            },
            'tmp_id': 'test-challenge',
          }),
        );
      } else if (values['otp'] != '012345') {
        r.response.statusCode = 401;
        r.response.write('{"exc_type":"AuthenticationError"}');
      } else {
        r.response.cookies.add(Cookie('sid', 'verified-session'));
        r.response.write('{"message":"Logged In","full_name":"Test Staff"}');
      }
      await r.response.close();
    });
    late LoginVerification challenge;
    try {
      await api.login('staff', 'synthetic');
      fail('A verification challenge is required');
    } on LoginVerification catch (e) {
      challenge = e;
    }
    expect(challenge.prompt, contains('registered email'));
    await expectLater(
      api.verifyLogin('staff', challenge, '000000'),
      throwsA(
        isA<ErpException>().having(
          (e) => e.message,
          'recovery',
          contains('code'),
        ),
      ),
    );
    await api.verifyLogin('staff', challenge, '012345');
    expect(api.userName, 'Test Staff');
    expect(api.account, 'staff');
    expect(requests, [
      {'usr': 'staff', 'pwd': 'synthetic'},
      {'otp': '000000', 'tmp_id': 'test-challenge'},
      {'otp': '012345', 'tmp_id': 'test-challenge'},
    ]);
  });

  test('an authenticated portal user can redeem an invitation before a fresh system login', () async {
    final visited = <String>[];
    server.listen((request) async {
      final action = request.uri.path.split('/').last;
      visited.add(action);
      request.response.headers.contentType = ContentType.json;
      if (action == 'login') {
        request.response.cookies.add(Cookie('sid', 'portal-session'));
        request.response.write('{"message":"No App"}');
      } else if (action.endsWith('accept_invite')) {
        expect(request.cookies.single.value, 'portal-session');
        expect(Uri.splitQueryString(await utf8.decoder.bind(request).join()), {
          'token': 'test-code',
        });
        request.response.write(
          '{"message":{"email":"person@example.invalid","company":"Example"}}',
        );
      } else {
        request.response.write('{}');
      }
      await request.response.close();
    });
    await api.redeemExistingInvitation(
      'test-code',
      () => api.login('person@example.invalid', 'test-password'),
    );
    expect(visited, [
      'login',
      'erp_extensions.onboarding.accept_invite',
      'logout',
    ]);
    await expectLater(
      api.login('person@example.invalid', 'test-password'),
      throwsA(isA<ErpException>()),
    );
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
  test('dashboard totals use company currency rather than mixing invoice currencies', () async {
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
                  fields.any((f) => f is Map && f['SUM'] == 'base_grand_total')
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
  });
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
