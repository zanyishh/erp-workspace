import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_reports.dart';

class ReportApi extends ErpApi {
  ReportApi() : super(Uri.parse('http://localhost:8081'));
  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async => {
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

void main() {
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
