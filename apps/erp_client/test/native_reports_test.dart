import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_reports.dart';

void main() {
  test(
    'hidden report columns retain positional alignment without appearing in the table or CSV',
    () {
      final report = NativeReportResult.fromJson({
        'columns': [
          {'fieldname': 'doctype', 'label': 'Source type', 'hidden': 1},
          {
            'fieldname': 'voucher',
            'label': 'Voucher',
            'fieldtype': 'Dynamic Link',
            'options': 'doctype',
          },
        ],
        'result': [
          ['Sales Order', 'SO-1'],
        ],
      });
      expect(report.columns.map((col) => col.label), ['Voucher']);
      expect(report.rows.single['doctype'], 'Sales Order');
      expect(report.csv(), '"Voucher"\r\n"SO-1"\r\n');
    },
  );

  test(
    'reports preserve numeric values and support map and positional rows',
    () {
      final report = NativeReportResult.fromJson({
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
          ['Sales', -2.75],
        ],
      });
      expect(report.rows[0]['debit'], 125.5);
      expect(report.rows[1]['account'], 'Sales');
      expect(report.rows[1]['debit'], -2.75);
    },
  );
  test('CSV quotes special text and neutralises spreadsheet formulas', () {
    final report = NativeReportResult.fromJson({
      'columns': [
        {'fieldname': 'name', 'label': 'Name'},
        {'fieldname': 'amount', 'label': 'Amount'},
      ],
      'result': [
        {'name': 'One, "Shop"', 'amount': -12.5},
        {'name': '=HYPERLINK("unsafe")', 'amount': 0},
      ],
    });
    expect(
      report.csv(),
      '"Name","Amount"\r\n"One, ""Shop""",-12.5\r\n"\'=HYPERLINK(""unsafe"")",0\r\n',
    );
  });
  test('prepared reports are not misrepresented as empty data', () {
    final report = NativeReportResult.fromJson({
      'prepared_report': true,
      'doc': {'status': 'Queued'},
    });
    expect(report.pending, isTrue);
  });
}
