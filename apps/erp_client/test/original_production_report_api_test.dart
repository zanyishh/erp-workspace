import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production summary calls only the scoped original report route',
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
          '/api/method/erp_extensions.migration.production_reports.summary',
        );
        final body = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(body['company'], 'Archive One');
        expect(body['group_by'], 'machine');
        expect(body['start'], '100');
        expect(body['page_length'], '100');
        expect(jsonDecode(body['filters']!), {
          'machine': '00',
          'party': 'Saved NAME',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {'company': 'Archive One'},
          }),
        );
        await request.response.close();
      });
      expect(
        await api.originalProductionSummary(
          'Archive One',
          groupBy: 'machine',
          start: 100,
          filters: {'machine': '00', 'party': 'Saved NAME'},
        ),
        {'company': 'Archive One'},
      );
    },
  );
}
