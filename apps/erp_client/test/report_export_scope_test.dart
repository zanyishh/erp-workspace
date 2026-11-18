import 'dart:async';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_reports.dart';
import 'package:erp_client/report_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Completer<NativeReportResult>? pending;
  @override
  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) async => {
    'doctype': 'Report',
    'reference': 'Sales Invoice',
    'fields': [],
    'can_export': true,
  };
  @override
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async =>
      pending?.future ??
      NativeReportResult.fromJson({
        'columns': [
          {'fieldname': 'party', 'label': 'Party'},
        ],
        'result': [
          {'party': 'Authorized result'},
        ],
      });
}

void main() {
  for (final change in ['access', 'company', 'api']) {
    testWidgets(
      'CSV picker cannot export obsolete data after $change changes',
      (t) async {
        final api = _Api(), replacement = change == 'api' ? _Api() : null;
        addTearDown(api.close);
        if (replacement != null) addTearDown(replacement.close);
        final directory = Directory.systemTemp.createTempSync(
          'erp-report-export-',
        );
        final file = File('${directory.path}/report.csv');
        addTearDown(() => directory.deleteSync(recursive: true));
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        final selected = Completer<String?>();
        var opened = false;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
          call,
        ) async {
          if (call.method == 'getSavePath') {
            opened = true;
            return selected.future;
          }
          return null;
        });
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          ),
        );
        Widget view(_Api client, String company) => MaterialApp(
          home: NativeReportScreen(
            api: client,
            name: 'Sales Register',
            company: company,
          ),
        );
        await t.pumpWidget(view(api, 'A'));
        await t.pumpAndSettle();
        await t.tap(find.text('Run report'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Export CSV'));
        await t.tap(find.text('Export CSV'));
        await t.pump();
        expect(opened, isTrue);
        if (change == 'access') {
          api.publishContext(_context(2));
        } else {
          await t.pumpWidget(
            view(replacement ?? api, change == 'company' ? 'B' : 'A'),
          );
        }
        await t.pumpAndSettle();
        selected.complete(file.path);
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(file.existsSync(), isFalse);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final session in [false, true]) {
    testWidgets(
      'CSV picker rejects a failed rerun with unchanged access revision, session $session',
      (t) async {
        final api = _Api();
        addTearDown(api.close);
        final directory = Directory.systemTemp.createTempSync(
          'erp-report-rejected-',
        );
        final file = File('${directory.path}/report.csv');
        addTearDown(() => directory.deleteSync(recursive: true));
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        final selected = Completer<String?>();
        var opened = false;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
          call,
        ) async {
          if (call.method == 'getSavePath') {
            opened = true;
            return selected.future;
          }
          return null;
        });
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          ),
        );
        await t.pumpWidget(
          MaterialApp(
            home: NativeReportScreen(
              api: api,
              name: 'Sales Register',
              company: 'A',
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Run report'));
        await t.pumpAndSettle();
        final pending = Completer<NativeReportResult>();
        api.pending = pending;
        await t.ensureVisible(find.text('Run report'));
        await t.tap(find.text('Run report'));
        await t.pump();
        await t.ensureVisible(find.text('Export CSV'));
        await t.tap(find.text('Export CSV'));
        await t.pump();
        expect(opened, isTrue);
        final revision = api.accessRevision;
        pending.completeError(
          ErpException(
            'Report permission expired.',
            permissionDenied: !session,
            sessionExpired: session,
          ),
        );
        await t.pumpAndSettle();
        expect(api.accessRevision, revision);
        expect(find.text('REPORT COULD NOT RUN'), findsOneWidget);
        selected.complete(file.path);
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(file.existsSync(), isFalse);
        expect(t.takeException(), isNull);
      },
    );
  }
}
