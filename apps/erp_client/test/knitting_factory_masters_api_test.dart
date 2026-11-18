import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'master register transmits its exact category with an independent page',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = ErpApi(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        expect(
          request.uri.path,
          '/api/method/erp_extensions.knitting.api.register',
        );
        final body = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(body, {
          'company': 'Mill',
          'collection': 'masters',
          'start': '100',
          'query': '',
          'category': 'Yarn colour',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {'category': 'Yarn colour'},
          }),
        );
        await request.response.close();
      });
      expect(
        await api.knittingRegister(
          'Mill',
          'masters',
          start: 100,
          category: 'Yarn colour',
        ),
        {'category': 'Yarn colour'},
      );
    },
  );
}
