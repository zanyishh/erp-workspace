import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _BatchProductionApi extends ErpApi {
  _BatchProductionApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic>? posted;
  String? version;
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posted = values;
    version = modified;
    return {
      'event': 'EVENT-1',
      'action': action,
      'data': {
        'batch': 'BATCH-1',
        'quantity_kg': values['quantity_kg'],
        'roll_count': values['rolls'],
      },
    };
  }
}

void main() {
  test('batch entry captures measured totals without individual weights', () {
    final actions = knitActions.where((a) => a.id == 'produce_batch');
    expect(actions, hasLength(1));
    final keys = actions.single.fields.map((f) => f.key);
    expect(keys, containsAll(['quantity_kg', 'rolls', 'inputs', 'loss_kg']));
    expect(keys, isNot(contains('weights_kg')));
    expect(knitActions.any((a) => a.id == 'produce'), isTrue);
  });
  for (final mismatch in [false, true]) {
    testWidgets(
      mismatch ? 'batch conservation rejects a 0.001 kg mismatch' : 'zero-count measured batch posts exact reviewed input and job version',
      (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _BatchProductionApi();
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            home: KnittingCommandForm(
              api: api,
              workspace: WorkspaceContext.fromJson({
                'company': 'Demo',
                'knitting_enabled': true,
                'capabilities': ['jobs', 'production'],
              }),
              action: knitActions.firstWhere((a) => a.id == 'produce_batch'),
              job: {
                'name': 'JOB-1',
                'modified': 'current',
                'material_mode': 'Customer',
                'programme': [
                  {
                    'id': 'P1',
                    'fabric': 'Jersey',
                    'dia': '30',
                    'target_kg': '88.000',
                  },
                ],
              },
              initial: {
                'programme_line': 'P1',
                'quantity_kg': '88.000',
                'rolls': '0',
                'loss_kg': mismatch ? '2.001' : '2.000',
                'shift': 'A',
                'warehouse': 'MAIN',
                'inputs': [
                  {'lot': 'LOT-1', 'quantity_kg': '90.000', 'units': '2'},
                ],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final review = find.text('Review entry');
        await tester.ensureVisible(review);
        await tester.tap(review);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (mismatch) {
          expect(find.textContaining('plus 2.001 kg of loss'), findsOneWidget);
          expect(find.text('Confirm & post'), findsNothing);
          expect(api.posted, isNull);
        } else {
          final confirm = find.text('Confirm & post');
          await tester.ensureVisible(confirm);
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(api.posted?['quantity_kg'], '88.000');
          expect(api.posted?['rolls'], '0');
          expect(api.posted?['weights_kg'], isNull);
          expect(api.posted?['inputs'], [
            {'lot': 'LOT-1', 'quantity_kg': '90.000', 'units': '2'},
          ]);
          expect(api.version, 'current');
          expect(find.textContaining('0 rolls'), findsWidgets);
          expect(find.text('Fabric batch · BATCH-1'), findsOneWidget);
        }
      },
    );
  }
}
