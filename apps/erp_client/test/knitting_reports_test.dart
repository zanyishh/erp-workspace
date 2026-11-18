import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_reports.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';

class ReportApi extends ErpApi {
  ReportApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic>? exported, lastRun;
  bool more = false;
  Completer<Map<String, dynamic>>? pendingExport;
  Completer<Map<String, dynamic>>? pendingLabels;
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => pendingLabels!.future;
  @override
  Future<Map<String, dynamic>> knittingExport(
    String company,
    String format,
    Map<String, dynamic> filters,
  ) async {
    exported = filters;
    if (pendingExport != null) return pendingExport!.future;
    throw const ErpException('Synthetic export captured.');
  }

  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async {
    lastRun = filters;
    return {
      'columns': [
        {'key': 'job', 'label': 'Job'},
        {'key': 'yarn_kg', 'label': 'Yarn kg'},
        {'key': 'shift', 'label': 'Shift'},
        {'key': 'fabric', 'label': 'Fabric'},
      ],
      'rows': [
        {
          'job': 'JOB-01',
          'yarn_kg': '10.000',
          'shift': 'A',
          'fabric': 'Fine jersey',
        },
      ],
      'summary': {'quantity_kg': '10.000'},
      'row_count': 1,
      'start': filters['start'] ?? 0,
      'has_more': more && filters['start'] == 0,
      'mode': 'as_of',
      'to_date': '2026-11-13',
      'basis': 'Closing custody',
    };
  }
}

void main() {
  test('stoppage entry supports optional shift and godown', () {
    final action = knitActions.firstWhere((a) => a.id == 'stoppage');
    for (final field in ['shift', 'warehouse']) {
      expect(
        action.fields.where((f) => f.key == field && f.optional),
        hasLength(1),
      );
    }
  });

  testWidgets(
    'phone knitting records show labelled values and expand in place',
    (t) async {
      final api = ReportApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('JOB-01'), findsOneWidget);
      expect(find.text('10.000'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              (w.axisDirection == AxisDirection.right ||
                  w.axisDirection == AxisDirection.left),
        ),
        findsNothing,
      );
      final details = find.text('More fields (1)');
      await t.ensureVisible(details);
      await t.tap(details);
      await t.pumpAndSettle();
      expect(find.text('Fine jersey'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'phone opens roll time and stoppage registers with their date and grouping',
    (t) async {
      final api = ReportApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final (title, report, group) in [
        ('Yarn Inward Register', 'yarn_inwards', null),
        ('Yarn Return Register', 'yarn_returns', null),
        ('Roll Time Register', 'rolls', null),
        ('Shiftwise Stoppage', 'stoppage', 'shift'),
        ('Machinewise Stoppage', 'stoppage', 'machine'),
      ]) {
        await t.tap(find.text('Report options'));
        await t.pumpAndSettle();
        await t.tap(find.byType(DropdownButtonFormField<String>).first);
        await t.pumpAndSettle();
        final option = find.text(title).hitTestable();
        await t.dragUntilVisible(
          option,
          find.byType(ListView).last,
          const Offset(0, -250),
        );
        await t.tap(option.last);
        await t.pumpAndSettle();
        expect(api.lastRun?['report'], report);
        expect(api.lastRun?['group_by'], group);
        expect(api.lastRun?['mode'], 'period');
        expect(find.text(title), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    },
  );
  for (final replacement in ['current', 'api', 'company', 'access']) {
    testWidgets(
      'pending save dialog $replacement context writes only when still authorized',
      (t) async {
        t.view.physicalSize = const Size(1440, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final old = ReportApi(), fresh = ReportApi();
        addTearDown(old.close);
        addTearDown(fresh.close);
        WorkspaceContext access(
          List<String> capabilities,
          String fingerprint,
        ) => WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'access_fingerprint': fingerprint,
          'capabilities': capabilities,
        });
        old.publishContext(access(['jobs', 'reports'], 'initial'));
        fresh.publishContext(access(['jobs', 'reports'], 'initial'));
        old.pendingExport = Completer<Map<String, dynamic>>();
        var selectedApi = old, company = 'Demo';
        late StateSetter rebuild;
        final directory = Directory.systemTemp.createTempSync(
          'erp-knit-export-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/export.csv');
        final selected = Completer<String?>(), opened = Completer<void>();
        const channel = MethodChannel('plugins.flutter.io/file_selector');
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'getSavePath') {
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
        await t.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                rebuild = set;
                return Scaffold(
                  body: KnittingReports(
                    api: selectedApi,
                    company: company,
                    job: 'JOB-1',
                    financialRead: false,
                  ),
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Export / print ▾'));
        await t.pumpAndSettle();
        await t.tap(find.text('Save CSV'));
        await t.pump();
        old.pendingExport!.complete({
          'name': 'export.csv',
          'mime': 'text/csv',
          'content': base64Encode('synthetic report'.codeUnits),
        });
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        expect(opened.isCompleted, isTrue);
        if (replacement == 'access') {
          old.publishContext(access(['jobs'], 'revoked'));
        } else if (replacement != 'current') {
          rebuild(() {
            if (replacement == 'api') {
              selectedApi = fresh;
            }
            if (replacement == 'company') {
              company = 'Other';
            }
          });
        }
        await t.pumpAndSettle();
        await t.runAsync(() async {
          selected.complete(file.path);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        if (replacement == 'current') {
          // File existence can precede the writer closing its Windows handle.
          // The export action returns to idle only after saveTo has completed.
          final busy = find.text('Preparing file…');
          var attempts = 0;
          while (busy.evaluate().isNotEmpty && attempts < 200) {
            attempts++;
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await t.pump();
          }
          expect(busy, findsNothing);
        }
        await t.pumpAndSettle();
        expect(file.existsSync(), replacement == 'current');
        if (replacement == 'current') {
          expect(file.readAsStringSync(), 'synthetic report');
        }
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final replacement in ['api', 'company', 'job', 'access', 'applied']) {
    for (final outcome in ['file', 'error']) {
      testWidgets(
        'late export $outcome is ignored after $replacement context changes',
        (t) async {
          t.view.physicalSize = const Size(1440, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final old = ReportApi(), fresh = ReportApi();
          addTearDown(old.close);
          addTearDown(fresh.close);
          WorkspaceContext access(String fingerprint) =>
              WorkspaceContext.fromJson({
                'company': 'Demo',
                'knitting_enabled': true,
                'access_fingerprint': fingerprint,
                'capabilities': ['jobs', 'reports'],
              });
          old.publishContext(access('initial'));
          fresh.publishContext(access('initial'));
          old.pendingExport = Completer<Map<String, dynamic>>();
          var selectedApi = old, company = 'Demo', job = 'JOB-OLD';
          late StateSetter rebuild;
          var saveDialogs = 0;
          const channel = MethodChannel('plugins.flutter.io/file_selector');
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
            call,
          ) async {
            if (call.method == 'getSavePath') {
              saveDialogs++;
              return null;
            }
            throw MissingPluginException();
          });
          addTearDown(
            () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              null,
            ),
          );
          await t.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, set) {
                  rebuild = set;
                  return Scaffold(
                    body: KnittingReports(
                      api: selectedApi,
                      company: company,
                      job: job,
                      financialRead: false,
                    ),
                  );
                },
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('Export / print ▾'));
          await t.pumpAndSettle();
          await t.tap(find.text('Save CSV'));
          await t.pump();
          if (replacement == 'access') {
            old.publishContext(access('refreshed'));
          } else if (replacement == 'applied') {
            await t.ensureVisible(find.text('Run report'));
            await t.tap(find.text('Run report'));
          } else {
            rebuild(() {
              if (replacement == 'api') {
                selectedApi = fresh;
              }
              if (replacement == 'company') {
                company = 'Other';
              }
              if (replacement == 'job') {
                job = 'JOB-NEW';
              }
            });
          }
          await t.pumpAndSettle();
          if (outcome == 'file') {
            old.pendingExport!.complete({
              'name': 'old-context.csv',
              'mime': 'text/csv',
              'content': base64Encode('synthetic'.codeUnits),
            });
          } else {
            old.pendingExport!.completeError(
              const ErpException('OLD-CONTEXT-EXPORT-ERROR'),
            );
          }
          await t.pumpAndSettle();
          expect(saveDialogs, 0);
          expect(find.textContaining('OLD-CONTEXT-EXPORT-ERROR'), findsNothing);
          expect(find.text('Preparing file…'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'late roll label choice cannot export into a replacement API and job',
    (t) async {
      t.view.physicalSize = const Size(1440, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final old = ReportApi(), fresh = ReportApi();
      addTearDown(old.close);
      addTearDown(fresh.close);
      old.pendingLabels = Completer<Map<String, dynamic>>();
      var selectedApi = old, job = 'JOB-OLD';
      late StateSetter rebuild;
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              rebuild = set;
              return Scaffold(
                body: KnittingReports(
                  api: selectedApi,
                  company: 'Demo',
                  job: job,
                  financialRead: false,
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Export / print ▾'));
      await t.pumpAndSettle();
      await t.tap(find.text('Print roll label'));
      await t.pump();
      rebuild(() {
        selectedApi = fresh;
        job = 'JOB-NEW';
      });
      await t.pump();
      old.pendingLabels!.complete({
        'rows': [
          {'name': 'ROLL-OLD', 'title': 'Old roll'},
        ],
        'has_more': false,
        'start': 0,
      });
      await t.pumpAndSettle();
      await t.tap(find.text('Old roll'));
      await t.pumpAndSettle();
      expect(old.exported, isNull);
      expect(fresh.exported, isNull);
      expect(find.textContaining('Synthetic export captured.'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('dimension drafts do not change paging or exports until Run', (
    t,
  ) async {
    final api = ReportApi()..more = true;
    addTearDown(api.close);
    t.view.physicalSize = const Size(1440, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnittingReports(
            api: api,
            company: 'Demo',
            financialRead: false,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final customer = find.byKey(const ValueKey('report-filter-customer'));
    expect(customer, findsOneWidget);
    await t.enterText(customer, 'INACTIVE-CUSTOMER');
    await t.tap(find.text('Run report'));
    await t.pumpAndSettle();
    expect(api.lastRun?['customer'], 'INACTIVE-CUSTOMER');
    await t.enterText(customer, 'UNAPPLIED');
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(api.lastRun?['customer'], 'INACTIVE-CUSTOMER');
    expect(api.lastRun?['start'], 100);
    await t.tap(find.text('Export / print ▾'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save CSV'));
    await t.pumpAndSettle();
    expect(api.exported?['customer'], 'INACTIVE-CUSTOMER');
    expect(find.textContaining('Applied:'), findsOneWidget);
  });

  testWidgets(
    'report dimensions are applicable and embedded order stays fixed',
    (t) async {
      final api = ReportApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(1440, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
              job: 'FIXED-JOB',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-filter-job')), findsNothing);
      expect(api.lastRun?['job'], 'FIXED-JOB');
      expect(find.byKey(const ValueKey('report-filter-machine')), findsNothing);
      await t.tap(find.text('Job reconciliation').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Component breakage').last);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('report-filter-employee')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('report-filter-gauge')), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('report-filter-employee')),
        'INACTIVE-EMPLOYEE',
      );
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      expect(api.lastRun?['employee'], 'INACTIVE-EMPLOYEE');
      await t.tap(find.text('Component breakage').first);
      await t.pumpAndSettle();
      await t.dragUntilVisible(
        find.text('Job reconciliation').hitTestable(),
        find.byType(ListView).last,
        const Offset(0, 280),
      );
      await t.tap(find.text('Job reconciliation').hitTestable().last);
      await t.pumpAndSettle();
      expect(api.lastRun?.containsKey('employee'), false);
      expect(api.lastRun?['start'], 0);
    },
  );
  testWidgets(
    'exports use the visible report until the operator runs the edited dates',
    (tester) async {
      final api = ReportApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final appliedDate = api.lastRun!['to_date'];
      if (find.text('Report options').evaluate().isNotEmpty) {
        await tester.tap(find.text('Report options'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Through · YYYY-MM-DD'),
        '2023-12-15',
      );
      await tester.ensureVisible(find.text('Export / print ▾'));
      await tester.tap(find.text('Export / print ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save CSV'));
      await tester.pumpAndSettle();
      expect(api.exported?['to_date'], appliedDate);
    },
  );
  testWidgets(
    'short phone fits report rows and gives the first row its correct number',
    (tester) async {
      tester.view.physicalSize = const Size(360, 510);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReportApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1–1 of 1'), findsOneWidget);
      await tester.ensureVisible(find.text('JOB-01'));
      expect(find.text('JOB-01').hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'removing report access hides cached results without reopening the route',
    (tester) async {
      final api = ReportApi();
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'capabilities': ['jobs', 'reports', 'financial_read'],
          'access_fingerprint': 'before',
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnittingReports(
              api: api,
              company: 'Demo',
              financialRead: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('10.000'), findsOneWidget);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'knitting_enabled': true,
          'capabilities': ['jobs'],
          'access_fingerprint': 'after',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('10.000'), findsNothing);
      expect(
        find.text('Your access to these reports changed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 834.0, 1440.0]) {
    testWidgets('reports stay readable and permission-scoped at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReportApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: KnittingReports(
                api: api,
                company: 'Demo',
                financialRead: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('10.000'), findsOneWidget);
      expect(find.text('Margin before overhead'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
