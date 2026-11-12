import 'dart:convert';
import 'dart:io';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';

Future<void> main() async {
  final user = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (user == null || password == null) {
    throw StateError(
      'Set ERP_USERNAME and ERP_PASSWORD for the verification session.',
    );
  }
  final api = ErpApi(
    Uri.parse(Platform.environment['ERP_URL'] ?? 'http://localhost:8080'),
  );
  try {
    await api.login(user, password);
    final snapshot = await api.snapshot(ReportingPeriod.month);
    final records = <String, int>{};
    for (final m in ErpModule.values) {
      records[m.name] = (await api.records(
        m,
        company: snapshot.company,
      )).length;
    }
    stdout.writeln(
      jsonEncode({
        'company': snapshot.company,
        'currency': snapshot.currency,
        'warehouses': snapshot.warehouses,
        'moduleRecords': records,
        'connection': 'passed',
      }),
    );
    await api.signOut();
  } finally {
    api.close();
  }
}
