import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_reports.dart';
import 'package:erp_client/report_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext _context(int revision) => WorkspaceContext.fromJson({
  'company': 'A',
  'companies': [
    {'name': 'A'},
    {'name': 'B'},
  ],
  'revision': revision,
});

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081')) {
    publishContext(_context(1));
  }
  Completer<Map<String, dynamic>>? pendingDefinition;
  Completer<void>? pendingQueue;
  final definitions = <String?>[];
  var queued = 0;
  bool prepared = false;
  @override
  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) {
    definitions.add(company);
    return company == 'A' && pendingDefinition != null
        ? pendingDefinition!.future
        : Future.value(_definition(company));
  }

  Map<String, dynamic> _definition(String? company) => {
    'doctype': 'Report',
    'reference': 'Sales Invoice',
    'can_export': true,
    'fields': [
      {'fieldname': 'party', 'fieldtype': 'Data', 'label': 'Party $company'},
    ],
  };
  @override
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async => NativeReportResult.fromJson(
    prepared
        ? {'prepared_report': true}
        : {
            'columns': [
              {'fieldname': 'party', 'label': 'Party'},
            ],
            'result': [
              {'party': filters['party'] ?? 'Visible $name'},
            ],
          },
  );
  @override
  Future<void> queueReport(String name, Map<String, dynamic> filters) {
    queued++;
    return pendingQueue?.future ?? Future.value();
  }
}

Widget _view(_Api api, String company) => MaterialApp(
  home: NativeReportScreen(api: api, name: 'Sales Register', company: company),
);
void main() {
  testWidgets(
    'an old report access refresh cannot hide the replacement company',
    (t) async {
      final api = _Api();
      addTearDown(api.close);
      await t.pumpWidget(_view(api, 'A'));
      await t.pumpAndSettle();
      final old = Completer<Map<String, dynamic>>();
      api.pendingDefinition = old;
      api.publishContext(_context(2));
      await t.pump();
      await t.pumpWidget(_view(api, 'B'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 10));
      }
      try {
        expect(find.text('Party B'), findsOneWidget);
      } finally {
        old.complete(api._definition('A'));
        await t.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'rerunning results cannot release a pending report generation command',
    (t) async {
      final api = _Api()..prepared = true;
      addTearDown(api.close);
      await t.pumpWidget(_view(api, 'A'));
      await t.pumpAndSettle();
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      final pending = Completer<void>();
      api.pendingQueue = pending;
      await t.ensureVisible(find.text('Generate report'));
      await t.tap(find.text('Generate report'));
      await t.pump();
      try {
        await t.ensureVisible(find.text('Run report'));
        await t.tap(find.text('Run report'));
        await t.pump();
        final generate = find.text('Generate report');
        if (generate.evaluate().isNotEmpty) {
          await t.ensureVisible(generate);
          await t.tap(generate);
          await t.pump();
        }
        expect(api.queued, 1);
      } finally {
        pending.complete();
        await t.pumpAndSettle();
      }
    },
  );
}
