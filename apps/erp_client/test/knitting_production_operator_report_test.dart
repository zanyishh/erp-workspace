import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_reports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OperatorReportApi extends ErpApi {
  _OperatorReportApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic> last = {};
  final lookups = <String>[];
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async {
    lookups.add(entity);
    return {
      'rows': entity == 'ProductionMachine'
          ? [
              {
                'name': 'PRIVATE-ORIGINAL-MACHINE',
                'title': 'Synthetic original machine',
                'machine_code': '007',
              },
            ]
          : [
              {
                'name': 'PRIVATE-ORIGINAL-PERSON',
                'title': 'Synthetic production person',
                'employee_number': '023',
              },
            ],
      'start': start,
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) async {
    last = Map.from(filters);
    return {
      'columns': [
        {'key': 'production_operator_label', 'label': 'Production operator'},
        {
          'key': 'production_operator_record',
          'label': 'Original person identity',
        },
      ],
      'rows': [
        {
          'production_operator_label': 'Unrecorded',
          'production_operator_record': 'PRIVATE-ORIGINAL-PERSON',
        },
      ],
      'summary': {},
      'row_count': 1,
      'start': filters['start'],
      'has_more': filters['start'] == 0,
      'mode': 'as_of',
      'to_date': '2026-11-15',
      'basis': 'Synthetic exact event snapshots',
    };
  }
}

void main() {
  for (final report in ['production', 'fabric', 'rolls']) {
    testWidgets(
      '$report original employee filter and grouping preserve opaque identity and readable label',
      (t) async {
        final api = _OperatorReportApi();
        addTearDown(api.close);
        t.view.physicalSize = const Size(1440, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
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
        await t.pumpAndSettle();
        await t.tap(find.text('Job reconciliation').first);
        await t.pumpAndSettle();
        await t.tap(
          find.text(switch (report) {
            'production' => 'Production & loss',
            'rolls' => 'Roll traceability',
            _ => 'Fabric in house',
          }).last,
        );
        await t.pumpAndSettle();
        final picker = find.byKey(
          const ValueKey('report-filter-production_operator'),
        );
        expect(picker, findsOneWidget);
        await t.ensureVisible(picker);
        await t.tap(picker);
        await t.pumpAndSettle();
        expect(find.text('PRIVATE-ORIGINAL-PERSON'), findsNothing);
        await t.tap(find.text('Synthetic production person'));
        await t.pumpAndSettle();
        expect(api.lookups, ['ProductionOperator']);
        expect(api.last['production_operator'], isNull);
        final group = find.byKey(ValueKey('group-$report'));
        await t.ensureVisible(group);
        await t.tap(group);
        await t.pumpAndSettle();
        await t.tap(find.text('Production operator · original employee').last);
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Run report'));
        await t.tap(find.text('Run report'));
        await t.pumpAndSettle();
        expect(api.last['production_operator'], 'PRIVATE-ORIGINAL-PERSON');
        expect(api.last['group_by'], 'production_operator');
        final applied = t.widget<Text>(find.textContaining('Applied:')).data!;
        expect(
          applied,
          contains('Group records: Production operator · original employee'),
        );
        expect(applied, contains('Synthetic production person · Employee 023'));
        expect(applied, isNot(contains('production_operator')));
        expect(
          t.widget<Text>(find.textContaining('Applied:')).data!,
          isNot(contains('PRIVATE-ORIGINAL-PERSON')),
        );
        expect(find.text('PRIVATE-ORIGINAL-PERSON'), findsNothing);
        expect(find.text('Unrecorded'), findsOneWidget);
        await t.ensureVisible(find.byTooltip('Clear production operator'));
        await t.tap(find.byTooltip('Clear production operator'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Next'));
        await t.tap(find.text('Next'));
        await t.pumpAndSettle();
        expect(api.last['production_operator'], 'PRIVATE-ORIGINAL-PERSON');
        expect(api.last['start'], 100);
        expect(api.last['group_by'], 'production_operator');
        final paged = t.widget<Text>(find.textContaining('Applied:')).data!;
        expect(
          paged,
          contains('Group records: Production operator · original employee'),
        );
        expect(paged, contains('Synthetic production person · Employee 023'));
        expect(paged, isNot(contains('production_operator')));
        await t.ensureVisible(find.text('Run report'));
        await t.tap(find.text('Run report'));
        await t.pumpAndSettle();
        expect(api.last['production_operator'], isNull);
        expect(api.last['start'], 0);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'shared original identities survive Production, Fabric and Rolls switching and clear on Jobs',
    (t) async {
      final api = _OperatorReportApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(1440, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
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
      await t.pumpAndSettle();
      Future<void> changeReport(String current, String next) async {
        await t.ensureVisible(find.text(current).first);
        await t.tap(find.text(current).first);
        await t.pumpAndSettle();
        final option = find.text(next).hitTestable();
        if (option.evaluate().isEmpty) {
          const order = [
            'Job reconciliation',
            'Fabric in house',
            'Roll traceability',
            'Production & loss',
          ];
          await t.dragUntilVisible(
            option,
            find.byType(ListView).last,
            Offset(
              0,
              order.indexOf(next) < order.indexOf(current) ? 250 : -250,
            ),
          );
        }
        await t.tap(option.last);
        await t.pumpAndSettle();
      }

      await changeReport('Job reconciliation', 'Production & loss');
      for (final choice in [
        ('production_operator', 'Synthetic production person'),
        ('production_machine', 'Synthetic original machine'),
      ]) {
        final picker = find.byKey(ValueKey('report-filter-${choice.$1}'));
        await t.ensureVisible(picker);
        await t.tap(picker);
        await t.pumpAndSettle();
        await t.tap(find.text(choice.$2));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.text('Run report'));
      await t.tap(find.text('Run report'));
      await t.pumpAndSettle();
      for (final pair in [
        ('Production & loss', 'Fabric in house'),
        ('Fabric in house', 'Roll traceability'),
        ('Roll traceability', 'Production & loss'),
      ]) {
        await changeReport(pair.$1, pair.$2);
        expect(api.last['production_operator'], 'PRIVATE-ORIGINAL-PERSON');
        expect(api.last['production_machine'], 'PRIVATE-ORIGINAL-MACHINE');
        expect(api.last['start'], 0);
        final applied = t.widget<Text>(find.textContaining('Applied:')).data!;
        expect(applied, contains('Synthetic production person · Employee 023'));
        expect(applied, contains('Synthetic original machine · Machine 007'));
        expect(applied, isNot(contains('PRIVATE-ORIGINAL')));
      }
      await changeReport('Production & loss', 'Job reconciliation');
      expect(api.last.containsKey('production_operator'), isFalse);
      expect(api.last.containsKey('production_machine'), isFalse);
      expect(
        find.byKey(const ValueKey('report-filter-production_operator')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('report-filter-production_machine')),
        findsNothing,
      );
      await changeReport('Job reconciliation', 'Fabric in house');
      expect(api.last.containsKey('production_operator'), isFalse);
      expect(api.last.containsKey('production_machine'), isFalse);
      expect(find.textContaining('Synthetic production person'), findsNothing);
      expect(find.textContaining('Synthetic original machine'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
