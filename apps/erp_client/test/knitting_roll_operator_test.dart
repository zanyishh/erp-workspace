import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _operatorLabel = 'Production operator · original employee (optional)';
final _workspace = WorkspaceContext.fromJson({
  'company': 'Demo',
  'knitting_enabled': true,
  'capabilities': ['jobs', 'production'],
});
final _job = <String, dynamic>{
  'name': 'JOB-1',
  'modified': 'v1',
  'material_mode': 'Customer',
  'programme': [
    {'id': 'P1', 'fabric': 'Jersey', 'dia': '30', 'target_kg': '100.000'},
  ],
};
Map<String, dynamic> _row() => {
  'programme_line': 'P1',
  'weights_kg': ['10.000'],
  'inputs': [
    {'lot': 'LOT-1', 'quantity_kg': '11.000', 'units': '0'},
  ],
  'loss_kg': '1.000',
  'shift': 'Day',
  'warehouse': 'MAIN',
};

class _OperatorApi extends ErpApi {
  _OperatorApi() : super(Uri.parse('http://localhost:8081')) {
    userName = 'Synthetic signer';
  }
  final posts = <Map<String, dynamic>>[];
  final lookups = <(String, String?)>[];
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async {
    lookups.add((entity, job));
    return {
      'rows': [
        {
          'name': 'PRIVATE-EMPLOYEE-A',
          'title': 'Synthetic operator',
          'employee_number': '007',
        },
        {
          'name': 'PRIVATE-EMPLOYEE-B',
          'title': 'Synthetic operator',
          'employee_number': '008',
        },
      ],
      'has_more': false,
      'start': start,
    };
  }

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posts.add({'action': action, 'values': values, 'modified': modified});
    return {'event': 'EVENT-1', 'action': action, 'data': {}};
  }
}

Future<void> _open(WidgetTester t, _OperatorApi api, String action) async {
  t.view.physicalSize = const Size(1440, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: KnittingCommandForm(
        api: api,
        workspace: _workspace,
        action: knitActions.firstWhere((a) => a.id == action),
        job: _job,
        initial: action == 'produce'
            ? _row()
            : {
                'entries': [_row(), _row()],
              },
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, String number, {int row = 0}) async {
  final field = find
      .ancestor(of: find.text(_operatorLabel), matching: find.byType(InkWell))
      .at(row);
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  await t.tap(find.text('Employee $number'));
  await t.pumpAndSettle();
}

Future<void> _review(WidgetTester t) async {
  await t.ensureVisible(find.text('Review entry'));
  await t.tap(find.text('Review entry'));
  await t.pumpAndSettle();
}

Future<void> _post(WidgetTester t) async {
  await t.ensureVisible(find.text('Confirm & post'));
  await t.tap(find.text('Confirm & post'));
  await t.pumpAndSettle();
}

void main() {
  test(
    'individual roll operator is an optional preserved-employee selector',
    () {
      final field = knitActions
          .firstWhere((a) => a.id == 'produce')
          .fields
          .singleWhere((f) => f.key == 'production_operator');
      expect(field.kind, 'ProductionOperator');
      expect(field.optional, isTrue);
    },
  );
  for (final action in ['produce', 'produce_bulk']) {
    testWidgets(
      '$action keeps original employee identities and exact numbers separate from signer',
      (t) async {
        final api = _OperatorApi();
        addTearDown(api.close);
        await _open(t, api, action);
        await _pick(t, '007');
        if (action == 'produce_bulk') {
          await _pick(t, '008', row: 1);
        }
        await _review(t);
        expect(find.text('Recorded by · Synthetic signer'), findsOneWidget);
        expect(find.text('Synthetic operator · Employee 007'), findsOneWidget);
        if (action == 'produce_bulk') {
          expect(
            find.text('Synthetic operator · Employee 008'),
            findsOneWidget,
          );
        }
        expect(find.textContaining('PRIVATE-EMPLOYEE'), findsNothing);
        await _post(t);
        final values = api.posts.single['values'] as Map;
        final rows = action == 'produce' ? [values] : values['entries'] as List;
        expect(
          rows.map((r) => r['production_operator']),
          action == 'produce'
              ? ['PRIVATE-EMPLOYEE-A']
              : ['PRIVATE-EMPLOYEE-A', 'PRIVATE-EMPLOYEE-B'],
        );
        for (final row in rows) {
          expect(row['weights_kg'], ['10.000']);
          expect(row.containsKey('operator'), isFalse);
          expect(row.containsKey('production_operator_label'), isFalse);
          expect(row.containsKey('production_operator_number'), isFalse);
        }
        expect(api.posts.single['modified'], 'v1');
        expect(
          api.lookups.every((l) => l == ('ProductionOperator', 'JOB-1')),
          isTrue,
        );
      },
    );
    testWidgets(
      '$action explicitly reviews unrecorded original employee without inventing signer attribution',
      (t) async {
        final api = _OperatorApi();
        addTearDown(api.close);
        await _open(t, api, action);
        await _review(t);
        expect(find.text('Recorded by · Synthetic signer'), findsOneWidget);
        expect(
          find.text('Production operator · Unrecorded'),
          findsNWidgets(action == 'produce' ? 1 : 2),
        );
        await _post(t);
        final values = api.posts.single['values'] as Map;
        final rows = action == 'produce' ? [values] : values['entries'] as List;
        for (final row in rows) {
          expect(row.containsKey('production_operator'), isFalse);
        }
      },
    );
  }
  testWidgets(
    'clearing individual original employee reviews and posts unrecorded',
    (t) async {
      final api = _OperatorApi();
      addTearDown(api.close);
      await _open(t, api, 'produce');
      await _pick(t, '008');
      final field = find
          .ancestor(
            of: find.text('Synthetic operator · Employee 008'),
            matching: find.byType(FormField<dynamic>),
          )
          .first;
      final clear = find.descendant(
        of: field,
        matching: find.text('Clear selection'),
      );
      await t.ensureVisible(clear);
      await t.tap(clear);
      await t.pumpAndSettle();
      await _review(t);
      expect(find.text('Production operator · Unrecorded'), findsOneWidget);
      expect(find.text('Synthetic operator · Employee 008'), findsNothing);
      await _post(t);
      expect(api.posts.single['values']['production_operator'], isNull);
    },
  );
}
