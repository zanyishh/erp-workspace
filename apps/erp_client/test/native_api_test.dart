import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';

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
    'workflow approval carries the reviewed modification timestamp',
    () async {
      String? modified;
      server.listen((r) async {
        final form = Uri.splitQueryString(await utf8.decoder.bind(r).join());
        modified = form['modified'];
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          '{"message":{"doc":{"doctype":"Example","name":"EX-1"}}}',
        );
        await r.response.close();
      });
      await api.transitionNative(
        'Example',
        'EX-1',
        'Approve',
        modified: '2026-11-12 10:00:00.123456',
      );
      expect(modified, '2026-11-12 10:00:00.123456');
    },
  );

  test(
    'native save posts editable values once and returns the saved name',
    () async {
      var writes = 0;
      Map<String, dynamic>? submitted;
      server.listen((request) async {
        writes++;
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        submitted = objectMap(jsonDecode(form['document']!));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {
              'doc': {'doctype': 'Example', 'name': 'EX-1', 'title': 'Native'},
            },
          }),
        );
        await request.response.close();
      });
      final schema = NativeSchema.fromJson({
        'doctype': 'Example',
        'fields': [
          {'fieldname': 'title', 'fieldtype': 'Data'},
          {'fieldname': 'locked', 'fieldtype': 'Data', 'read_only': 1},
        ],
      });
      final saved = await api.saveNative(schema, {
        'doctype': 'Example',
        '__islocal': 1,
        'title': 'Native',
        'locked': 'do not send',
      });
      expect(saved.data['name'], 'EX-1');
      expect(submitted, {
        'doctype': 'Example',
        '__islocal': 1,
        'title': 'Native',
      });
      expect(writes, 1);
    },
  );

  test(
    'server validation is readable and failed writes are never retried',
    () async {
      var requests = 0;
      server.listen((r) async {
        requests++;
        r.response.statusCode = 417;
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'exc_type': 'ValidationError',
            '_server_messages': jsonEncode([
              jsonEncode({'message': '<b>Customer</b> is required.'}),
            ]),
            'exc': 'secret internal traceback',
          }),
        );
        await r.response.close();
      });
      final schema = NativeSchema.fromJson({
        'doctype': 'Example',
        'fields': [],
      });
      await expectLater(
        api.saveNative(schema, {'doctype': 'Example', '__islocal': 1}),
        throwsA(
          isA<ErpException>().having(
            (e) => e.message,
            'message',
            'Customer is required.',
          ),
        ),
      );
      expect(requests, 1);
    },
  );
}
