import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/task_planner.dart';

class _Tasks extends ErpApi {
  _Tasks() : super(Uri.parse('http://localhost:8081'));
  final requests = <(String?, String?, int)>[];
  @override
  Future<Map<String, dynamic>> taskView(
    String company, {
    String? month,
    String? status,
    int start = 0,
  }) async {
    requests.add((month, status, start));
    return {
      'statuses': ['Open', 'Working'],
      'has_more': start == 0 && month == null && status == null,
      'rows': [
        if (status == null || status == 'Open')
          {
            'name': start == 0 ? 'TASK-1' : 'TASK-2',
            'subject': start == 0 ? 'Inspect shipment' : 'Pack shipment',
            'status': 'Open',
            'exp_start_date': '${month ?? '2031-04'}-01 10:00:00',
            'exp_end_date': '${month ?? '2031-04'}-04 11:00:00',
          },
      ],
    };
  }
}

void main() {
  testWidgets(
    'board pages and filters tasks, and the monthly calendar shows a spanning task on each covered day',
    (t) async {
      final api = _Tasks();
      addTearDown(api.close);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 760);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          home: TaskPlanner(api: api, company: 'Synthetic'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Inspect shipment'), findsOneWidget);
      await t.tap(find.text('Load more tasks (1 shown)'));
      await t.pumpAndSettle();
      expect(find.text('Pack shipment'), findsOneWidget);
      expect(api.requests.last, (null, null, 1));
      await t.tap(find.byTooltip('Filter by task status'));
      await t.pumpAndSettle();
      await t.tap(find.text('Working'));
      await t.pumpAndSettle();
      expect(find.text('No tasks match this view.'), findsOneWidget);
      await t.tap(find.byTooltip('Filter by task status'));
      await t.pumpAndSettle();
      await t.tap(find.text('All statuses').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Calendar'));
      await t.pumpAndSettle();
      await t.tap(find.text('3'));
      await t.pumpAndSettle();
      expect(find.text('Inspect shipment'), findsOneWidget);
      await t.tap(find.text('6'));
      await t.pumpAndSettle();
      expect(find.text('No scheduled tasks on this day.'), findsOneWidget);
      final previous = api.requests.last.$1;
      await t.tap(find.byTooltip('Next month'));
      await t.pumpAndSettle();
      expect(api.requests.last.$1, isNot(previous));
      expect(t.takeException(), isNull);
    },
  );
}
