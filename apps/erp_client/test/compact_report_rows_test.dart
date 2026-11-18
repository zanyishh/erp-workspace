import 'package:erp_client/design.dart';
import 'package:erp_client/native_reports.dart';
import 'package:erp_client/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('phone report pages and linked details on ${platform.name}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final report = NativeReportResult.fromJson({
        'columns': [
          {'fieldname': 'name', 'label': 'Reference', 'fieldtype': 'Data'},
          {'fieldname': 'amount', 'label': 'Amount', 'fieldtype': 'Currency'},
          {'fieldname': 'status', 'label': 'Status', 'fieldtype': 'Data'},
          {
            'fieldname': 'party',
            'label': 'Party',
            'fieldtype': 'Dynamic Link',
            'options': 'party_type',
          },
          {'fieldname': 'party_type', 'label': 'Internal type', 'hidden': 1},
        ],
        'result': [
          for (var i = 1; i <= 11; i++)
            {
              'name': 'Row $i',
              'amount': 12000 + i,
              'status': 'Draft',
              'party': 'Mill $i',
              'party_type': 'Customer',
            },
        ],
      });
      (String, String)? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme.copyWith(platform: platform),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NativeReportTable(
                result: report,
                onDocument: (type, name) => opened = (type, name),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaginatedDataTable), findsNothing);
      expect(find.text('Rows 1–10 of 11'), findsOneWidget);
      expect(find.text('Row 11'), findsNothing);
      await tester.tap(find.byTooltip('Next rows'));
      await tester.pumpAndSettle();
      expect(find.text('Rows 11–11 of 11'), findsOneWidget);
      expect(find.text('12011'), findsOneWidget);
      expect(find.text('Mill 11'), findsNothing);
      await tester.tap(find.text('More fields (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Internal type'), findsNothing);
      await tester.tap(find.text('Mill 11'));
      expect(opened, ('Customer', 'Mill 11'));
      expect(tester.takeException(), isNull);
    });
  }
}
