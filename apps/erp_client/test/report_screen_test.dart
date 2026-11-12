import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/report_screen.dart';
import 'package:erp_client/native_reports.dart';

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
}
