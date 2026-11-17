import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Guest-style forbidden native responses recover without confusing real permission denials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
    var signedIn = false, renewals = 0, probes = 0;
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      r.response.headers.contentType = ContentType.json;
      if (r.uri.path.endsWith('/login')) {
        r.response.cookies.add(Cookie('sid', 'session'));
        r.response.write('{"message":"Logged In"}');
      } else if (r.uri.path.endsWith('.session_status')) {
        probes++;
        r.response.write(
          jsonEncode({
            'message': {'signed_in': signedIn},
          }),
        );
      } else {
        r.response.statusCode = 403;
        r.response.write('{"exc_type":"PermissionError"}');
      }
      await r.response.close();
    });
    await api.login('user', 'password');
    api.onSessionExpired = () async {
      renewals++;
      signedIn = true;
      await api.login('user', 'password');
      return true;
    };
    await expectLater(
      api.printOptions('Example', 'EX-1'),
      throwsA(
        isA<ErpException>().having((e) => e.sessionExpired, 'renewed', false),
      ),
    );
    expect(renewals, 1);
    await expectLater(
      api.printOptions('Example', 'EX-1'),
      throwsA(
        isA<ErpException>().having(
          (e) => e.permissionDenied,
          'permission denied',
          true,
        ),
      ),
    );
    expect(renewals, 1);
    expect(probes, 2);
  });

  test(
    'expired native writes renew once and wait for a manual retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      var logins = 0, writes = 0, renewals = 0;
      server.listen((r) async {
        await utf8.decoder.bind(r).join();
        r.response.headers.contentType = ContentType.json;
        if (r.uri.path.endsWith('/login')) {
          logins++;
          r.response.cookies.add(Cookie('sid', 'session-$logins'));
          r.response.write('{"message":"Logged In"}');
        } else {
          writes++;
          if (logins == 1) {
            r.response.statusCode = 401;
            r.response.write('{"exc_type":"SessionExpired"}');
          } else {
            r.response.write('{"message":{"formats":["Standard"]}}');
          }
        }
        await r.response.close();
      });
      await api.login('test-user', 'test-password');
      api.onSessionExpired = () async {
        renewals++;
        await api.login('test-user', 'test-password');
        return true;
      };
      await expectLater(
        api.printOptions('Example', 'EX-1'),
        throwsA(
          isA<ErpException>().having(
            (e) => e.sessionExpired,
            'already renewed',
            false,
          ),
        ),
      );
      expect(writes, 1);
      expect(renewals, 1);
      expect(await api.printOptions('Example', 'EX-1'), ['Standard']);
      expect(writes, 2);
    },
  );
}
