import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_models.dart';

void main() {
  test('sales scale keeps returns and positive totals inside the chart', () {
    final scale = SalesScale([-1000, 500]);
    expect(scale.fraction(-1000), 0);
    expect(scale.fraction(500), 1);
    expect(scale.fraction(0), closeTo(2 / 3, .0001));
    expect(SalesScale([0]).fraction(0).isFinite, isTrue);
  });

  test('calendar boundaries survive daylight-saving changes', () {
    final range = ReportingPeriod.days30.range(DateTime(2026, 11, 1, 17));
    expect(DateRange.iso(range.start), '2026-10-03');
    expect(DateRange.iso(range.end), '2026-11-02');
    expect(range.end.hour, 0);
  });
  test('reporting periods include timestamped records on the final day', () {
    final range = ReportingPeriod.month.range(DateTime(2026, 11, 12, 16));
    expect(range.start, DateTime(2026, 11, 1));
    expect(range.end, DateTime(2026, 11, 13));
    final filters = ErpModule.manufacturing.filters('ERP Evaluation', range);
    expect(filters, contains(equals(['company', '=', 'ERP Evaluation'])));
    expect(
      filters,
      contains(equals(['planned_start_date', '<', '2026-11-13'])),
    );
    expect(ErpModule.stock.filters('ERP Evaluation', range), isEmpty);
  });

  test(
    'original document links safely encode record names and retain origin',
    () {
      final uri = ErpModule.accounts.uri(
        Uri.parse('http://localhost:8080'),
        name: 'INV/2026 #1?x=yes',
      );
      expect(uri.host, 'localhost');
      expect(uri.pathSegments, ['app', 'sales-invoice', 'INV/2026 #1?x=yes']);
      expect(uri.query, isEmpty);
    },
  );

  test('records keep real labels and search without hiding original names', () {
    final record = ErpRecord({
      'name': 'ITEM-0001',
      'item_name': 'Paper cartons',
      'item_group': 'Packaging',
      'disabled': 0,
    }, ErpModule.stock);
    expect(record.title, 'Paper cartons');
    expect(record.subtitle, 'ITEM-0001');
    expect(record.matches('CARTON'), isTrue);
    expect(record.matches('item-0001'), isTrue);
    expect(record.matches('steel'), isFalse);
  });
}
