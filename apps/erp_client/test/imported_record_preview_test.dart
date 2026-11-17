import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:erp_client/imported_history.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/imported_record_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'imported_record_pdf_test.dart' show sourceRecord;

class OriginalRecordApi extends ErpApi {
  OriginalRecordApi() : super(Uri.parse('http://127.0.0.1:8082'));
  bool denied = false, printable = true;
  List<Map<String, dynamic>>? detailTables;
  @override
  Future<Map<String, dynamic>> importedHistoryDetail(
    String company,
    String name,
  ) async => {
    ...sourceRecord(),
    'name': name,
    'family': 'job',
    'target_links': [],
    'record_printable': printable,
    'printable': false,
    if (detailTables != null) 'tables': detailTables,
  };
  String? wrongCompany, wrongName;
  Completer<Map<String, dynamic>>? pending;
  final reads = <(String, String)>[];
  @override
  Future<Map<String, dynamic>> importedRecordPrintData(
    String company,
    String name,
  ) async {
    reads.add((company, name));
    if (denied) {
      throw const ErpException(
        'Original record access was revoked.',
        permissionDenied: true,
      );
    }
    if (pending != null) return pending!.future;
    return {
      ...sourceRecord(),
      'company': wrongCompany ?? company,
      'source_record': wrongName ?? name,
    };
  }
}

void main() {
  Future<void> open(WidgetTester t, OriginalRecordApi api) async {
    await t.pumpWidget(
      MaterialApp(
        home: ImportedRecordPreviewScreen(
          api: api,
          company: 'Synthetic Knitting',
          name: 'history-job-42',
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'source preview fetches its immutable identity and revocation blocks export',
    (t) async {
      final api = OriginalRecordApi();
      addTearDown(api.close);
      await open(t, api);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(api.reads, [('Synthetic Knitting', 'history-job-42')]);
      api.denied = true;
      await t.tap(find.text('Export PDF'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Original record access was revoked.'), findsOneWidget);
      expect(api.reads.length, 2);
    },
  );
  for (final companyMismatch in [true, false]) {
    testWidgets('scope mismatch $companyMismatch exposes no export', (t) async {
      final api = OriginalRecordApi();
      addTearDown(api.close);
      if (companyMismatch) {
        api.wrongCompany = 'Other';
      } else {
        api.wrongName = 'Other';
      }
      await open(t, api);
      await t.pumpAndSettle();
      expect(find.text('Export PDF'), findsNothing);
      expect(find.textContaining('unexpected scope'), findsOneWidget);
    });
  }
  testWidgets('access change during pending export blocks stale side effects', (
    t,
  ) async {
    final api = OriginalRecordApi();
    addTearDown(api.close);
    await open(t, api);
    api.pending = Completer<Map<String, dynamic>>();
    await t.tap(find.text('Export PDF'));
    await t.pump();
    api.accessRevision++;
    api.accessReady = false;
    api.pending!.complete(sourceRecord());
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(t.takeException(), isNull);
    expect(find.textContaining('Access changed'), findsOneWidget);
  });
  for (final allowed in [true, false]) {
    testWidgets(
      'original detail print visibility follows server permission $allowed',
      (t) async {
        final api = OriginalRecordApi()..printable = allowed;
        addTearDown(api.close);
        await t.pumpWidget(
          MaterialApp(
            home: ImportedHistoryDetailScreen(
              api: api,
              company: 'Synthetic Knitting',
              name: 'history-job-42',
            ),
          ),
        );
        await t.pumpAndSettle();
        final action = find.text('Print original record');
        expect(action, allowed ? findsOneWidget : findsNothing);
        expect(find.text('Print original invoice'), findsNothing);
      },
    );
  }
  testWidgets(
    'revoked permission while save dialog is pending writes no file',
    (t) async {
      final api = OriginalRecordApi();
      addTearDown(api.close);
      final directory = Directory.systemTemp.createTempSync('erp-source-save-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/must-not-exist.pdf');
      final selected = Completer<String?>(), opened = Completer<void>();
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getSavePath') {
          expect(
            (call.arguments as Map)['suggestedName'],
            'ORDER-42 - Orders - Original source copy.pdf',
          );
          opened.complete();
          return selected.future;
        }
        throw MissingPluginException();
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await open(t, api);
      await t.tap(find.text('Export PDF'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(opened.isCompleted, isTrue);
      api.denied = true;
      selected.complete(file.path);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Original record access was revoked.'), findsOneWidget);
      expect(file.existsSync(), isFalse);
    },
  );

  testWidgets('company and record changes discard the old pending preview', (
    t,
  ) async {
    final api = OriginalRecordApi();
    addTearDown(api.close);
    final old = Completer<Map<String, dynamic>>();
    api.pending = old;
    await open(t, api);
    api.pending = null;
    await t.pumpWidget(
      MaterialApp(
        home: ImportedRecordPreviewScreen(
          api: api,
          company: 'New Company',
          name: 'new-source',
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    old.complete(sourceRecord());
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(t.takeException(), isNull);
    expect(find.text('Export PDF'), findsOneWidget);
    api.denied = true;
    await t.tap(find.text('Export PDF'));
    await t.pump();
    expect(api.reads.last, ('New Company', 'new-source'));
    expect(find.text('Original record access was revoked.'), findsOneWidget);
  });
  testWidgets(
    'fully masked tables keep original detail and print action reachable',
    (t) async {
      final api = OriginalRecordApi()
        ..detailTables = [
          {
            'title': 'Original items',
            'columns': [],
            'rows': [{}, {}],
          },
        ];
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: ImportedHistoryDetailScreen(
            api: api,
            company: 'Synthetic Knitting',
            name: 'history-job-42',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('No visible fields in 2 original lines.'),
        findsOneWidget,
      );
      expect(find.text('Print original record'), findsOneWidget);
      expect(find.text('22.500'), findsNothing);
    },
  );
  testWidgets('unreviewed nonempty rows without columns remain rejected', (
    t,
  ) async {
    final api = OriginalRecordApi()
      ..detailTables = [
        {
          'title': 'Broken source',
          'columns': [],
          'rows': [
            {'amount': '22.500'},
          ],
        },
      ];
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: ImportedHistoryDetailScreen(
          api: api,
          company: 'Synthetic Knitting',
          name: 'history-job-42',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('This imported table is unavailable.'), findsOneWidget);
    expect(find.text('Print original record'), findsNothing);
    expect(find.text('22.500'), findsNothing);
  });
}
