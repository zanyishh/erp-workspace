import 'dart:io';
import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/master_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImportApi extends ErpApi {
  _ImportApi() : super(Uri.parse('http://localhost:8081'));
  final stages = <String>[];
  Completer<Map<String, dynamic>>? pending;
  bool loseResponse = false, imported = false;
  @override
  Future<Map<String, dynamic>> importMasters(
    String type,
    String company,
    String stage, {
    String? content,
  }) async {
    expect(type, 'Customer');
    expect(company, 'North Mill');
    expect(content, contains('North Shop'));
    stages.add(stage);
    if (stage == 'confirm') {
      if (pending != null) return pending!.future;
      imported = true;
      if (loseResponse) throw const ErpException('Response lost');
    }
    if (stage == 'preview' && imported) {
      return {'count': 1, 'already_imported': true};
    }
    return {
      'count': 1,
      'columns': ['customer_name'],
      'sample': [
        ['North Shop'],
      ],
    };
  }
}

void main() {
  Future<void> ready(WidgetTester t, _ImportApi api) async {
    final dir = Directory.systemTemp.createTempSync('erp-import-recovery');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/customers.csv')
      ..writeAsStringSync('customer_name\nNorth Shop');
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'openFile' ? [file.path] : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MasterImportScreen(
                    api: api,
                    doctype: 'Customer',
                    company: 'North Mill',
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
    await t.tap(find.text('Choose CSV'));
    for (
      var i = 0;
      i < 40 && find.text('Import 1 record').evaluate().isEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
  }

  testWidgets('master import blocks Back until the pending write completes', (
    t,
  ) async {
    final api = _ImportApi()..pending = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await ready(t, api);
    await t.tap(find.text('Import 1 record'));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(MasterImportScreen), findsOneWidget);
    api.pending!.complete({'count': 1});
    await t.pumpAndSettle();
    expect(find.text('Imported 1 record.'), findsOneWidget);
  });
  testWidgets(
    'master import checks its existing digest receipt after a lost response',
    (t) async {
      final api = _ImportApi()..loseResponse = true;
      addTearDown(api.close);
      await ready(t, api);
      await t.tap(find.text('Import 1 record'));
      await t.pumpAndSettle();
      await t.tap(find.text('Check import outcome'));
      await t.pumpAndSettle();
      expect(api.stages, ['preview', 'confirm', 'preview']);
      expect(find.text('Already imported · 1 record.'), findsOneWidget);
    },
  );

  testWidgets(
    'file is previewed before confirmation and can only be posted once from its receipt',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('erp-import-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/customers.csv')
        ..writeAsStringSync('customer_name\nNorth Shop');
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'openFile' ? [file.path] : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final api = _ImportApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: MasterImportScreen(
            api: api,
            doctype: 'Customer',
            company: 'North Mill',
          ),
        ),
      );
      await t.tap(find.text('Choose CSV'));
      for (
        var i = 0;
        i < 40 && find.text('Import 1 record').evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump(const Duration(milliseconds: 25));
      }
      expect(api.stages, ['preview']);
      expect(find.text('North Shop'), findsOneWidget);
      await t.tap(find.text('Import 1 record'));
      await t.pumpAndSettle();
      expect(api.stages, ['preview', 'confirm']);
      expect(find.text('Imported 1 record.'), findsOneWidget);
      expect(find.text('Import 1 record'), findsNothing);
    },
  );
}
