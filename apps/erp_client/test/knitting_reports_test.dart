import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_reports.dart';
import 'package:erp_client/workspace_context.dart';

class ReportApi extends ErpApi {
  ReportApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic>? exported, lastRun;
  @override
  Future<Map<String, dynamic>> knittingExport(
    String company,
    String format,
    Map<String, dynamic> filters,
  ) async {
    exported = filters;
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
      ],
      'rows': [
        {'job': 'JOB-01', 'yarn_kg': '10.000'},
      ],
      'summary': {'quantity_kg': '10.000'},
      'row_count': 1,
      'start': 0,
      'has_more': false,
      'mode': 'as_of',
      'to_date': '2026-11-13',
      'basis': 'Closing custody',
    };
  }
}

void main() {
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
      await tester.enterText(
        find.widgetWithText(TextField, 'Through · YYYY-MM-DD'),
        '2023-12-15',
      );
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
