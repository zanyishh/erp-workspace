import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';

Future<void> main() async {
  final uri = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://localhost:8081',
  );
  if (!['localhost', '127.0.0.1'].contains(uri.host) || uri.port != 8081) {
    throw StateError('Only the isolated native test server is allowed.');
  }
  final api = ErpApi(uri);
  try {
    await api.login(
      Platform.environment['ERP_USERNAME']!,
      Platform.environment['ERP_PASSWORD']!,
    );
    if ((await api.nativeCatalog()).site != 'native-test.localhost') {
      throw StateError('Refusing non-test site.');
    }
    const company = 'ERP Native Verification';
    final w = await api.selectCompany(company);
    final nextLoginHome = await api.workspaceContext();
    if (nextLoginHome.company != company || !nextLoginHome.enabled) {
      throw StateError('Selected knitting workspace was not retained.');
    }
    if (!w.enabled) {
      throw StateError('Seed the synthetic knitting setup first.');
    }
    final settings = await api.industrySettings(company);
    final warehouse = (settings['settings'] as Map)['warehouse'] as String;
    final token = 'http-${DateTime.now().microsecondsSinceEpoch}';
    var n = 0;
    String? job;
    Future<Map<String, dynamic>> post(
      String action,
      Map<String, dynamic> values,
    ) async {
      String? modified;
      if (values['job'] != null) {
        final lookup = await api.knittingLookup(
          company,
          'Job',
          values['job'] as String,
        );
        modified =
            ((lookup['rows'] as List).firstWhere(
                  (r) => r['name'] == values['job'],
                ) as Map)['modified']
                as String;
      }
      return api.knittingCommand(
        company,
        action,
        values,
        '$token-${n++}',
        modified: modified,
      );
    }

    Future<Map<String, dynamic>> guide() async {
      final selected = await api.knittingSnapshot(company, job: job);
      return Map<String, dynamic>.from(
        selected.rows('jobs').single['workflow'] as Map,
      );
    }

    void verify(bool ok, String message) {
      if (!ok) throw StateError(message);
    }

    final created = await post('create_job', {
      'customer': 'Demo Knitting Mills',
      'kind': 'Order',
      'material_mode': 'Customer',
      'target_kg': '88.000',
      'rate': '100.00',
      'programme': [
        {
          'id': 'P1',
          'fabric': 'Single jersey',
          'target_kg': '88.000',
          'dia': '30',
          'gauge': '24',
          'knit_type': 'Tubular',
        },
      ],
      'notes': 'Synthetic Dart HTTP acceptance cycle',
    });
    job = (created['data'] as Map)['job'] as String;
    verify(
      ((await guide())['remaining_lines'] as List).single == 'P1',
      'New programme missing from job guide.',
    );
    final received = await post('receive_yarn', {
      'job': job,
      'item': 'DEMO-KNIT-YARN',
      'material_owner': 'Customer',
      'party': 'Demo Knitting Mills',
      'quantity_kg': '100.000',
      'warehouse': warehouse,
    });
    final lot = (received['data'] as Map)['lot'];
    verify(
      (await guide())['only_lot'] == lot,
      'Guide lost the received yarn lot.',
    );
    final produced = await post('produce', {
      'job': job,
      'programme_line': 'P1',
      'shift': 'A',
      'weights_kg': ['44.000', '44.000'],
      'inputs': [
        {'lot': lot, 'quantity_kg': '90.000'},
      ],
      'loss_kg': '2.000',
      'warehouse': warehouse,
    });
    final rolls = List<String>.from((produced['data'] as Map)['rolls'] as List);
    final inspection = (await guide())['inspection'] as Map;
    verify(
      inspection['count'] == 2 && inspection['only'] == null,
      'Two rolls must require an inspection choice.',
    );
    for (final roll in rolls) {
      await post('quality', {
        'job': job,
        'roll': roll,
        'decision': 'Released',
        'remarks': 'Synthetic HTTP check',
      });
    }
    final delivery = await post('deliver', {'job': job, 'rolls': rolls});
    verify(
      (await guide())['only_delivery'] == delivery['event'],
      'Incorrect invoice source in job guide.',
    );
    final invoice = await post('invoice', {
      'job': job,
      'deliveries': [delivery['event']],
      'no_tax': true,
    });
    if ((invoice['data'] as Map)['amount'] != '8800.00') {
      throw StateError('Incorrect invoice total.');
    }
    await post('return_yarn', {
      'job': job,
      'lot': lot,
      'quantity_kg': '10.000',
    });
    await post('close_job', {'job': job});
    await post('reopen_job', {
      'job': job,
      'reason': 'Inspect returned demo fabric',
    });
    final credit = await post('credit_invoice', {
      'job': job,
      'invoice_event': invoice['event'],
      'quantity_kg': '44.000',
      'reason': 'Synthetic returned roll',
    });
    if (credit['data']['amount'] != '-4400.00') {
      throw StateError('Credit amount mismatch.');
    }
    final returned = await post('return_fabric', {
      'job': job,
      'delivery': delivery['event'],
      'rolls': [rolls.first],
      'reason': 'Synthetic return received',
    });
    verify(
      ((await guide())['inspection'] as Map)['only'] == rolls.first,
      'Returned roll needs reinspection.',
    );
    final afterReturn =
        (await api.knittingSnapshot(
              company,
              job: job,
            )).rows('jobs').single['balances']
            as Map;
    if (afterReturn['fabric_kg'] != '44.000' ||
        afterReturn['billed_kg'] != '44.000') {
      throw StateError('Returned roll did not reconcile to source billing.');
    }
    for (final source in [returned, credit, invoice]) {
      await post('cancel_event', {
        'job': job,
        'event': source['event'],
        'reason': 'Synthetic correction',
      });
    }
    final replacement = await post('invoice', {
      'job': job,
      'deliveries': [delivery['event']],
      'no_tax': true,
    });
    if (replacement['data']['amount'] != '8800.00') {
      throw StateError('Replacement invoice mismatch.');
    }
    await post('close_job', {'job': job});
    final snap = await api.knittingSnapshot(company);
    final row = snap.rows('jobs').firstWhere((r) => r['name'] == job);
    final b = row['balances'] as Map;
    for (final key in [
      'yarn_kg',
      'fabric_kg',
      'unbilled_kg',
      'subcontract_kg',
    ]) {
      if (b[key] != '0.000') throw StateError('Unreconciled $key');
    }
    final status = await api.knittingCommandStatus(company, '$token-0');
    if (status['event'] != created['event']) {
      throw StateError('Request receipt mismatch.');
    }
    final name = (replacement['data'] as Map)['invoice'] as String;
    final pdf = await api.printPdf('Sales Invoice', name, 'Standard');
    if (!ascii.decode(pdf.bytes.take(5).toList()).startsWith('%PDF-')) {
      throw StateError('Invalid invoice print.');
    }
    stdout.writeln(
      jsonEncode({
        'site': 'native-test.localhost',
        'job': job,
        'invoice': name,
        'cancelled_invoice': invoice['data']['invoice'],
        'cancelled_credit': credit['data']['invoice'],
        'credit_amount': credit['data']['amount'],
        'physical_return_kg': afterReturn['fabric_kg'],
        'amount': '8800.00',
        'balances': b,
        'httpCycle': 'passed',
        'selectedJobGuidance': 'passed',
        'receiptLookup': 'passed',
        'invoicePdf': 'passed',
      }),
    );
    await api.signOut();
  } finally {
    api.close();
  }
}
