import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/history_models.dart';

List<Map<String, dynamic>> _rows(Object? value) =>
    (value as List).cast<Map<String, dynamic>>();

String _value(Object? value) => value == null
    ? 'Not recorded'
    : value == ''
    ? 'Blank'
    : value.toString();

/// Preserve original strings without monetary rounding or inferred totals.
Future<Uint8List> buildImportedRecordPdf(Map<String, dynamic> data) async {
  return renderOriginalRecordPdf(OriginalRecordData.forRendering(data));
}

/// Render an immutable source projection without making a second data copy.
Future<Uint8List> renderOriginalRecordPdf(OriginalRecordData record) async {
  final data = record.data;
  final fields = _rows(data['fields']), tables = _rows(data['tables']);
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Manrope-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Manrope-SemiBold.ttf'),
  );
  final ink = PdfColor.fromHex('#252724'), muted = PdfColor.fromHex('#656960');
  final peach = PdfColor.fromHex('#f4d6c2');
  final doc = pw.Document();
  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(font: bold, fontSize: 12, color: ink),
    ),
  );
  pw.Widget line(String label, Object? value) => pw.Text(
    '$label: ${_value(value)}',
    overflow: pw.TextOverflow.span,
    style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 10000,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(bottom: 14),
        decoration: pw.BoxDecoration(color: peach),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Original source copy',
              style: pw.TextStyle(font: bold, color: ink, fontSize: 14),
            ),
            pw.Text(
              '${data['company']} · ${data['document_label']} · ${_value(data['reference'])}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Preserved source facts · Read-only copy',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (_) => [
        heading(data['title'] as String),
        line('Original date', data['original_date']),
        if (data['effective_date'] != null &&
            data['effective_date'] != data['original_date'])
          line('Effective date', data['effective_date']),
        line(
          'Date basis',
          const {
            'original': 'Original transaction date',
            'approved_opening': 'Approved opening date',
            'undated_review': 'Original date unavailable',
            'not_applicable': 'Not applicable',
          }[data['date_basis']],
        ),
        line('Review status', data['review_status']),
        heading('Original fields'),
        for (final field in fields)
          line(field['label'] as String, field['value']),
        for (final table in tables) ...[
          heading(table['title'] as String),
          ..._table(table, line, heading, peach),
        ],
        if ((data['review_notes'] as List).isNotEmpty) ...[
          heading('Source review notes'),
          for (final note in data['review_notes'] as List)
            pw.Text(
              note as String,
              overflow: pw.TextOverflow.span,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
        ],
      ],
    ),
  );
  return doc.save();
}

List<pw.Widget> _table(
  Map<String, dynamic> table,
  pw.Widget Function(String, Object?) line,
  pw.Widget Function(String) heading,
  PdfColor peach,
) {
  final columns = _rows(table['columns']), rows = _rows(table['rows']);
  if (rows.isEmpty) return [pw.Text('No original lines recorded.')];
  if (columns.isEmpty) {
    return [
      pw.Text(
        'No visible fields in ${rows.length} original ${rows.length == 1 ? 'line' : 'lines'}.',
      ),
    ];
  }
  final compact =
      columns.length <= 4 &&
      rows.every(
        (row) => columns.every((c) {
          final value = _value(row[c['key']]);
          return value.length <= 80 && !value.contains(RegExp(r'[\r\n]'));
        }),
      );
  if (compact) {
    return [
      pw.TableHelper.fromTextArray(
        headers: [for (final c in columns) c['label'] as String],
        data: [
          for (final row in rows)
            [for (final c in columns) _value(row[c['key']])],
        ],
        headerDecoration: pw.BoxDecoration(color: peach),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.topLeft,
        cellPadding: const pw.EdgeInsets.all(6),
      ),
    ];
  }
  // Labelled lines let wide rows and long source text span pages at readable size.
  return [
    for (var index = 0; index < rows.length; index++) ...[
      heading('Original line ${index + 1}'),
      for (final c in columns)
        line(c['label'] as String, rows[index][c['key']]),
    ],
  ];
}
