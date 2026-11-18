import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/bank_statement_import.dart';
import 'package:erp_client/erp_api.dart';

class StatementApi extends ErpApi {
  StatementApi() : super(Uri.parse('http://localhost:8081'));
  final stages = <String>[];
  Completer<Map<String, dynamic>>? pendingImport;
  bool loseResponse = false;
  bool committed = false;
  @override
  Future<Map<String, dynamic>> importBankCsv(
    String company,
    String account,
    String stage,
    String content,
    Map<String, String> mapping,
    String format,
  ) async {
    stages.add(stage);
    if (stage == 'columns') {
      return {
        'headers': ['Date', 'Credit', 'Memo'],
        'mapping': {'date': 'Date', 'deposit': 'Credit', 'description': 'Memo'},
      };
    }
    if (stage == 'preview') {
      return {
        'new_count': committed ? 0 : 1,
        'duplicates': committed ? 1 : 0,
        'currency': 'INR',
        'rows': [
          {
            'line': 2,
            'date': '2026-11-14',
            'deposit': '65',
            'withdrawal': '0',
            'description': 'Local receipt',
            'reference_number': '',
            'existing': committed ? 'BT-1' : null,
          },
        ],
      };
    }
    if (pendingImport != null) return pendingImport!.future;
    committed = true;
    if (loseResponse) throw const ErpException('Response lost');
    return {'created': 1, 'duplicates': 0};
  }
}

void main() {
  Future<void> ready(WidgetTester t, StatementApi api) async {
    t.view.physicalSize = const Size(750, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BankStatementImport(
                    api: api,
                    company: 'Mill',
                    bank: 'Operating',
                    pickFile: () async => XFile.fromData(
                      Uint8List.fromList(
                        utf8.encode(
                          'Date,Credit,Memo\n2026-11-14,65,Local receipt',
                        ),
                      ),
                      name: 'statement.csv',
                      path: 'statement.csv',
                    ),
                  ),
                ),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open import'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose CSV file'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Preview statement lines'));
    await t.tap(find.text('Preview statement lines'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Import 1 statement line'));
  }

  testWidgets('bank import cannot be abandoned while the write is pending', (
    t,
  ) async {
    final api = StatementApi()
      ..pendingImport = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await ready(t, api);
    await t.tap(find.text('Import 1 statement line'));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(BankStatementImport), findsOneWidget);
    api.pendingImport!.complete({'created': 1, 'duplicates': 0});
    await t.pumpAndSettle();
    expect(
      find.text('Imported 1 statement line. Skipped 0 duplicates.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'lost bank import response checks existing lines without importing again',
    (t) async {
      final api = StatementApi()..loseResponse = true;
      addTearDown(api.close);
      await ready(t, api);
      await t.tap(find.text('Import 1 statement line'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Check import outcome'));
      await t.tap(find.text('Check import outcome'));
      await t.pumpAndSettle();
      expect(api.stages.where((s) => s == 'import').length, 1);
      expect(
        find.textContaining('All statement lines are present'),
        findsOneWidget,
      );
      expect(find.text('statement.csv'), findsOneWidget);
    },
  );

  testWidgets('bank CSV is mapped and previewed before explicit import', (
    t,
  ) async {
    t.view.physicalSize = const Size(750, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = StatementApi();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: BankStatementImport(
          api: api,
          company: 'Mill',
          bank: 'Operating',
          pickFile: () async => XFile.fromData(
            Uint8List.fromList(
              utf8.encode('Date,Credit,Memo\n2026-11-14,65,Local receipt'),
            ),
            name: 'statement.csv',
            path: 'statement.csv',
          ),
        ),
      ),
    );
    await t.tap(find.text('Choose CSV file'));
    await t.pumpAndSettle();
    expect(api.stages, ['columns']);
    await t.scrollUntilVisible(find.text('Preview statement lines'), 300);
    await t.tap(find.text('Preview statement lines'));
    await t.pumpAndSettle();
    expect(api.stages, ['columns', 'preview']);
    await t.ensureVisible(find.text('Import 1 statement line'));
    await t.tap(find.text('Import 1 statement line'));
    await t.pumpAndSettle();
    expect(api.stages.last, 'import');
    expect(
      find.text('Imported 1 statement line. Skipped 0 duplicates.'),
      findsOneWidget,
    );
  });
}
