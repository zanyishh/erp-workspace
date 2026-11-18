import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs register transmits exact customer identity and applied job-date bounds', () async {
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
        'collection': 'jobs',
        'start': '100',
        'query': '456/26',
        'state': 'Running',
        'customer': 'KP-CUSTOMER-001',
        'from_date': '2026-04-01',
        'to_date': '2026-11-15',
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'message': {'customer': 'KP-CUSTOMER-001'},
        }),
      );
      await request.response.close();
    });
    expect(
      await api.knittingRegister(
        'Mill',
        'jobs',
        start: 100,
        query: '456/26',
        state: 'Running',
        customer: 'KP-CUSTOMER-001',
        fromDate: '2026-04-01',
        toDate: '2026-11-15',
      ),
      {'customer': 'KP-CUSTOMER-001'},
    );
  });
}
