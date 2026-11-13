import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/report_screen.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_reports.dart';

class _ReportApi extends ErpApi {
  _ReportApi() : super(Uri.parse('http://localhost:8081'));
  @override
  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) async => {
    'doctype': 'Report',
    'reference': 'Sales Invoice',
    'can_export': true,
    'fields': [
      {'fieldname': 'party', 'fieldtype': 'Data', 'label': 'Party'},
    ],
  };

  @override
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async => NativeReportResult.fromJson({
    'columns': [
      {'fieldname': 'party', 'label': 'Party'},
    ],
    'result': [
      {'party': filters['party'] ?? 'All customers'},
    ],
  });
}

void main() {
  testWidgets(
    'report links open native records and preserve displayed amounts',
    (tester) async {
      final result = NativeReportResult.fromJson({
        'columns': [
          {
            'fieldname': 'account',
            'label': 'Account',
            'fieldtype': 'Link',
            'options': 'Account',
          },
          {'fieldname': 'debit', 'label': 'Debit', 'fieldtype': 'Currency'},
        ],
        'result': [
          {'account': 'Cash', 'debit': 125.5},
        ],
      });
      (String, String)? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeReportTable(
              result: result,
              onDocument: (type, name) => selected = (type, name),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('125.5'), findsOneWidget);
      await tester.tap(find.text('Cash'));
      expect(selected, ('Account', 'Cash'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing report filters hides previous rows and exports until rerun',
    (tester) async {
      final api = _ReportApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeReportScreen(api: api, name: 'Sales Register'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run report'));
      await tester.pumpAndSettle();
      expect(find.text('All customers'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Blue Mill');
      await tester.pumpAndSettle();
      expect(find.text('All customers'), findsNothing);
      expect(find.text('Export CSV'), findsNothing);
      await tester.tap(find.text('Run report'));
      await tester.pumpAndSettle();
      expect(find.text('Blue Mill'), findsNWidgets(2));
    },
  );
}
