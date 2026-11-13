import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';

void main() {
  test(
    'stale record responses are distinguishable from field validation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = 417;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"exc_type":"TimestampMismatchError"}');
        await request.response.close();
      });
      await expectLater(
        api.nativeDocument('Sales Order', name: 'SO-1'),
        throwsA(
          isA<ErpException>().having((e) => e.staleDocument, 'stale', true),
        ),
      );
    },
  );
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
    'malformed hierarchy data is rejected before it reaches the screen',
    () async {
      server.listen((r) async {
        await r.drain<void>();
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          '{"message":{"nodes":[{"name":null}],"has_more":false,"can_create":true}}',
        );
        await r.response.close();
      });
      await expectLater(
        api.nativeTree('Warehouse'),
        throwsA(isA<ErpException>()),
      );
    },
  );

  test(
    'hierarchy requests preserve company, branch and page; child drafts preserve parent',
    () async {
      final forms = <Map<String, String>>[];
      server.listen((r) async {
        forms.add(Uri.splitQueryString(await utf8.decoder.bind(r).join()));
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          r.uri.path.endsWith('tree_children')
              ? '{"message":{"nodes":[{"name":"STORE","title":"Stores","expandable":false}],"has_more":false,"can_create":true}}'
              : '{"message":{"doc":{"doctype":"Warehouse","__islocal":1,"parent_warehouse":"ROOT"}}}',
        );
        await r.response.close();
      });
      final result = await api.nativeTree(
        'Warehouse',
        parent: 'ROOT',
        company: 'Company A',
        start: 50,
      );
      expect((result['nodes'] as List).single['name'], 'STORE');
      final draft = await api.nativeDocument(
        'Warehouse',
        company: 'Company A',
        treeParent: 'ROOT',
      );
      expect(draft.data['parent_warehouse'], 'ROOT');
      expect(forms[0], {
        'doctype': 'Warehouse',
        'parent': 'ROOT',
        'company': 'Company A',
        'start': '50',
      });
      expect(forms[1], {
        'doctype': 'Warehouse',
        'company': 'Company A',
        'tree_parent': 'ROOT',
      });
    },
  );

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
