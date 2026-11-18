// Synthetic recovery-lifecycle check; never submits a business write. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/operations/data/erp_operation_repository.dart';
import 'package:erp_client/features/operations/presentation/pending_operations_view_model.dart';

Future<void> main() async {
  final origin = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://127.0.0.1:8081',
  );
  if (!{'localhost', '127.0.0.1'}.contains(origin.host) ||
      origin.port != 8081 ||
      origin.scheme != 'http') {
    throw StateError('Recovery verification requires the local test site.');
  }
  final username = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (username == null || password == null) {
    throw StateError('Set synthetic verification credentials.');
  }
  final api = ErpApi(origin);
  PendingOperationsViewModel? model;
  try {
    await api.login(username, password);
    final catalog = await api.nativeCatalog();
    if (catalog.site != 'native-test.localhost') {
      throw StateError('Refusing to write outside native-test.localhost.');
    }
    const company = 'ERP Native Verification';
    await api.workspaceContext(company: company);
    final id = 'architecture-recovery-${DateTime.now().microsecondsSinceEpoch}';
    await api.beginOperation(company, 'invoice', id);
    final repository = ErpOperationRepository(api: api, company: company);
    model = PendingOperationsViewModel(repository);
    await model.load();
    for (
      var pages = 0;
      !model.rows.any((row) => row.requestId == id) &&
          model.more &&
          pages < 100;
      pages++
    ) {
      await model.nextPage();
    }
    if (model.error != null ||
        !model.rows.any(
          (row) => row.requestId == id && row.state == 'prepared',
        )) {
      throw StateError('Prepared recovery reference was not listed.');
    }
    await model.checkStatus(id);
    if (model.rows.singleWhere((row) => row.requestId == id).state !=
        'prepared') {
      throw StateError('Checking status changed the unposted outcome.');
    }
    await model.closeUnposted(id);
    final closed = model.rows.singleWhere((row) => row.requestId == id);
    if (closed.state != 'closed' || closed.savedName != null) {
      throw StateError('Closing an unposted reference created a saved record.');
    }
    await model.dismiss(id);
    if (model.error != null || model.rows.any((row) => row.requestId == id)) {
      throw StateError('Acknowledged recovery reference remained visible.');
    }
    final receipt = await repository.status(id);
    if (receipt.state != 'closed' || receipt.savedName != null) {
      throw StateError('Recovery lifecycle unexpectedly posted a record.');
    }
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'company': company,
        'recoveryLifecycle': 'prepared -> closed -> acknowledged',
        'businessWrites': 0,
      }),
    );
    await api.signOut();
  } finally {
    model?.dispose();
    api.close();
  }
}
