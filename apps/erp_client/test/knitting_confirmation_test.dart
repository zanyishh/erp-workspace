import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';

class ConfirmationApi extends ErpApi {
  ConfirmationApi() : super(Uri.parse('http://localhost:8081'));
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async => {
    'event': 'EVENT-1',
    'action': action,
    'data': {
      'quantity_kg': '88.000',
      'rolls': ['ROLL-1', 'ROLL-2'],
      'sources': [
        {'dn_detail': 'INTERNAL-ROW', 'invoice_item': 'INTERNAL-ITEM'},
      ],
      'voucher_type': null,
    },
  };
}

void main() {
  test('both general and job material forms capture physical counts', () {
    for (final action in knitActions.where(
      (a) => [
        'receive_yarn',
        'return_yarn',
        'allocate_yarn',
        'transfer_yarn',
        'move_yarn',
        'subcontract_issue',
        'subcontract_return',
      ].contains(a.id),
    )) {
      expect(
        action.fields.any((f) => f.key == 'units'),
        isTrue,
        reason: '${action.title} must capture bags/cones',
      );
    }
  });
  testWidgets(
    'confirmed entry shows the outcome without internal allocation data',
    (tester) async {
      final api = ConfirmationApi();
      addTearDown(api.close);
      final workspace = WorkspaceContext.fromJson({
        'company': 'Demo',
        'knitting_enabled': true,
        'capabilities': ['jobs', 'delivery'],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: workspace,
            action: knitActions.firstWhere((a) => a.id == 'deliver'),
            job: {'name': 'JOB-1', 'modified': 'current'},
            initial: {
              'rolls': ['ROLL-1', 'ROLL-2'],
            },
          ),
        ),
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm & post'));
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dn detail'), findsNothing);
      expect(find.textContaining('INTERNAL-ROW'), findsNothing);
      expect(find.text('88.000 kg'), findsOneWidget);
      expect(find.text('2 rolls'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    },
  );
}
