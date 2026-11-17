import 'package:erp_client/erp_api.dart';
import 'package:erp_client/operational_handoffs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class HandoffApi extends ErpApi {
  HandoffApi() : super(Uri.parse('http://localhost:8081'));
  String? submitted;
  @override
  Future<Map<String, dynamic>> receiptInspectionItems(String receipt) async => {
    'modified': 'v1',
    'rows': [
      {
        'row': 'r1',
        'index': 1,
        'item': 'Yarn',
        'quantity': '10',
        'inspection': null,
      },
      {
        'row': 'r2',
        'index': 2,
        'item': 'Yarn',
        'quantity': '4',
        'inspection': null,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> inspectReceipt(
    String receipt,
    String row,
    String sample,
    String modified,
  ) async {
    submitted = '$receipt/$row/$sample/$modified';
    return {'name': 'QI-1'};
  }

  @override
  Future<Map<String, dynamic>> maintenanceLogs(String plan) async => {
    'logs': [
      {
        'name': 'LOG-1',
        'due_date': '2026-11-14',
        'task_name': 'Calibrate',
        'maintenance_status': 'Planned',
      },
    ],
  };
}

void main() {
  testWidgets(
    'receipt inspection binds sample to the selected source row; maintenance opens due log',
    (t) async {
      final api = HandoffApi();
      addTearDown(api.close);
      HandoffTarget? target;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => Column(
                children: [
                  for (final name in [
                    'Inspect receipt items',
                    'Maintenance logs',
                  ])
                    TextButton(
                      onPressed: () async {
                        target = await openOperationalAction(
                          c,
                          api,
                          name,
                          'source',
                        );
                      },
                      child: Text(name),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Inspect receipt items'));
      await t.pumpAndSettle();
      await t.tap(find.text('Row 2 · Yarn'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '5');
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create draft'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField), '2');
      await t.pump();
      await t.tap(find.text('Create draft'));
      await t.pumpAndSettle();
      expect(target?.name, 'QI-1');
      expect(api.submitted, 'source/r2/2/v1');
      await t.tap(find.text('Maintenance logs'));
      await t.pumpAndSettle();
      await t.tap(find.text('Calibrate · Planned'));
      await t.pumpAndSettle();
      expect(target?.type, 'Asset Maintenance Log');
      expect(target?.name, 'LOG-1');
    },
  );
}
