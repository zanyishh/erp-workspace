import 'dart:io';

import 'package:erp_client/imported_record_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sourceRecord({int rows = 2, int columns = 2}) => {
  'version': 1,
  'company': 'Synthetic Knitting',
  'source_record': 'history-job-42',
  'source_copy': true,
  'document_label': 'Orders',
  'title': 'Synthetic original order',
  'reference': 'ORDER-42',
  'original_date': null,
  'effective_date': '2023-04-01',
  'date_basis': 'approved_opening',
  'review_status': 'Review source state',
  'fields': [
    {'label': 'Header quantity', 'value': '0.000'},
    {'label': 'Empty', 'value': ''},
    {'label': 'Missing', 'value': null},
    {'label': 'Exact decimal', 'value': '123456789012345.67000'},
  ],
  'tables': [
    {
      'title': 'Original lines',
      'columns': [
        for (var c = 0; c < columns; c++) {'key': 'c$c', 'label': 'Column $c'},
      ],
      'rows': [
        for (var r = 0; r < rows; r++)
          {for (var c = 0; c < columns; c++) 'c$c': 'ROW-$r-COL-$c'},
      ],
    },
  ],
  'review_notes': ['Original header and details remain separate.'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<String> extracted(Map<String, dynamic> data, String kind) async {
    final directory = Directory(
      Platform.environment['ERP_RECORD_SAMPLE_OUTPUT'] ??
          '${Directory.systemTemp.path}/erp-record-pdf-tests',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/$kind.pdf');
    await file.writeAsBytes(await buildImportedRecordPdf(data));
    final text = await Process.run('pdftotext', ['-layout', file.path, '-']);
    expect(text.exitCode, 0);
    return text.stdout as String;
  }

  test(
    'source copy preserves dates, zero, null, blank and exact decimals',
    () async {
      final text = await extracted(sourceRecord(), 'short');
      expect(text, isNot(contains('history-job-42')));
      expect(text, isNot(contains('approved_opening')));
      expect(text, contains('Date basis: Approved opening date'));
      for (final value in [
        'Original source copy',
        'ORDER-42',
        'Original date: Not recorded',
        'Effective date: 2023-04-01',
        '0.000',
        '123456789012345.67000',
        'Empty: Blank',
        'Missing: Not recorded',
        'ROW-1-COL-1',
      ]) {
        expect(text, contains(value));
      }
    },
  );
  test(
    'long wide source tables keep every cell and repeat page identification',
    () async {
      final text = await extracted(
        sourceRecord(rows: 160, columns: 9),
        'wide-long',
      );
      for (var r = 0; r < 160; r++) {
        for (var c = 0; c < 9; c++) {
          expect(text, contains('ROW-$r-COL-$c'));
        }
      }
      expect('Original source copy'.allMatches(text).length, greaterThan(2));
      expect('ORDER-42'.allMatches(text).length, greaterThan(2));
    },
  );
  test('long notes and cell content paginate without cutting the final words', () async {
    final data = sourceRecord();
    data['review_notes'] = [
      "${List.filled(900, 'Long original note.').join(' ')} FINAL-NOTE-MARKER",
    ];
    data['tables'] = [
      {
        'title': 'Long source detail',
        'columns': [
          {'key': 'note', 'label': 'Note'},
        ],
        'rows': [
          {
            'note':
                "${List.filled(900, 'Source detail.').join(' ')} FINAL-CELL-MARKER",
          },
        ],
      },
    ];
    final text = await extracted(data, 'long-content');
    expect(text, contains('FINAL-NOTE-MARKER'));
    expect(text, contains('FINAL-CELL-MARKER'));
  });
  test(
    'matching effective date is not repeated and long headers fit',
    () async {
      final data = sourceRecord();
      data['original_date'] = '2020-02-29';
      data['effective_date'] = '2020-02-29';
      data['date_basis'] = 'original';
      data['company'] = List.filled(15, 'Synthetic Knitting').join(' ');
      data['reference'] = List.filled(14, 'Original-42').join(' ');
      final text = await extracted(data, 'long-header');
      expect(text, contains('Original date: 2020-02-29'));
      expect(text, isNot(contains('Effective date:')));
      expect(text, contains('ROW-1-COL-1'));
    },
  );
  test(
    'short multiline source cells span pages and retain following rows',
    () async {
      final data = sourceRecord();
      data['tables'] = [
        {
          'title': 'Multiline original details',
          'columns': [
            {'key': 'note', 'label': 'Note'},
          ],
          'rows': [
            {'note': 'A${List.filled(78, "\n").join()}B'},
            {'note': 'FOLLOWING-ROW-MARKER'},
          ],
        },
      ];
      final text = await extracted(data, 'short-multiline');
      expect(RegExp(r'^B$', multiLine: true).hasMatch(text), isTrue);
      expect(text, contains('FOLLOWING-ROW-MARKER'));
      expect(
        text.split('\f').where((page) => page.trim().isNotEmpty).length,
        greaterThan(1),
      );
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
  test('fully masked rows remain printable without revealing values', () async {
    final data = sourceRecord();
    data['tables'] = [
      {
        'title': 'Original items',
        'columns': [],
        'rows': [{}, {}],
      },
    ];
    final text = await extracted(data, 'masked-table');
    expect(text, contains('Original items'));
    expect(text, contains('No visible fields in 2 original lines.'));
    expect(text, isNot(contains('22.500')));
    expect(text, isNot(contains('2.500')));
  });
  test('renderer refuses an unmarked or malformed source copy', () async {
    for (final change in [
      {'source_copy': false},
      {'version': 2},
      {
        'tables': [
          {
            'title': 'Broken',
            'columns': [],
            'rows': [
              {'x': 'hidden'},
            ],
          },
        ],
      },
    ]) {
      await expectLater(
        buildImportedRecordPdf({...sourceRecord(), ...change}),
        throwsFormatException,
      );
    }
  });
}
