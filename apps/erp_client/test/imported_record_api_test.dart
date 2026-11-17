import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'imported_record_pdf_test.dart' show sourceRecord;

void main() {
  test(
    'operational print API uses exact reviewed route and company/name',
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
          '/api/method/erp_extensions.migration.printing.record_data',
        );
        final body = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(body, {
          'company': 'Synthetic Knitting',
          'name': 'history-job-42',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'message': sourceRecord()}));
        await request.response.close();
      });
      expect(
        (await api.importedRecordPrintData(
          'Synthetic Knitting',
          'history-job-42',
        ))['source_record'],
        'history-job-42',
      );
    },
  );
}
