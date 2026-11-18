import 'dart:convert';
import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice_number.dart';
import '../models/invoice_paper.dart';
import '../models/invoice_templates.dart';

part 'invoice_art_direction_service.dart';
part 'invoice_compact_pdf_service.dart';

extension InvoicePdfPaper on InvoicePaper {
  PdfPageFormat get pageFormat =>
      PdfPageFormat(widthMm * PdfPageFormat.mm, heightMm * PdfPageFormat.mm);
}

String _s(dynamic value) => value?.toString().trim() ?? '';
List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];
bool _yes(dynamic v) => v == true || v == 1 || v == '1';
bool _nonzero(dynamic v) => !RegExp(r'^[-+]?0*(?:\.0*)?$').hasMatch(_s(v));
String _date(dynamic raw) {
  final value = _s(raw);
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

List<String> _chunks(String value, int limit) {
  final lines = <String>[];
  var current = '';
  for (final block in value.split('\n')) {
    for (final word in block.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      if (current.isNotEmpty && current.length + word.length + 1 > limit) {
        lines.add(current);
        current = '';
      }
      if (word.length > limit) {
        final chars = word.runes.toList();
        for (var i = 0; i < chars.length; i += limit) {
          final part = String.fromCharCodes(
            chars.sublist(i, math.min(i + limit, chars.length)),
          );
          if (i + limit < chars.length) {
            lines.add(part);
          } else {
            current = part;
          }
        }
      } else {
        current = current.isEmpty ? word : '$current $word';
      }
    }
    if (current.isNotEmpty) lines.add(current);
    current = '';
  }
  return lines;
}

Future<Map<String, ByteData>>? _fontFiles;
Future<Map<String, ByteData>> _fonts() => _fontFiles ??= () async {
  final out = <String, ByteData>{};
  for (final f in [
    'Manrope-Regular',
    'Manrope-ExtraBold',
    'Manrope-SemiBold',
    'BarlowCondensed-SemiBold',
  ]) {
    out[f] = await rootBundle.load('assets/fonts/$f.ttf');
  }
  return out;
}();

Future<Uint8List> buildInvoicePdf(
  InvoiceTemplate template,
  Map<String, dynamic> invoice, {
  InvoicePaper paper = InvoicePaper.a4,
}) async {
  if (_yes(invoice['source_copy'])) {
    final rows = _rows(invoice['items']);
    final date = _s(invoice['posting_date']);
    final decimal = RegExp(r'^[+-]?\d+(?:\.\d+)?$');
    if (_s(invoice['source_reference']).isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
        rows.isEmpty ||
        rows.any(
          (row) =>
              row['item_name'] is! String ||
              row['description'] != null && row['description'] is! String ||
              [
                'qty',
                'rate',
                'amount',
              ].any((key) => !decimal.hasMatch(_s(row[key]))),
        ) ||
        !decimal.hasMatch(_s(invoice['grand_total']))) {
      throw const FormatException(
        'The original invoice needs its recorded date, quantities, rates and totals to print.',
      );
    }
    invoice = {
      ...invoice,
      'terms':
          '${_s(invoice['terms'])}\nOriginal source reference: ${_s(invoice['source_reference'])}'
              .trim(),
    };
  }
  if (_s(invoice['name']).isEmpty ||
      _s(invoice['currency']).isEmpty ||
      _s(invoice['grand_total']).isEmpty) {
    throw const FormatException(
      'The invoice needs its reference, currency and posted total to print.',
    );
  }
  final data = await _fonts();
  final art = paper == InvoicePaper.a4 && _materialStyles.contains(template.id)
      ? pw.MemoryImage(
          (await rootBundle.load('assets/invoice_art/${template.id}.jpg'))
              .buffer
              .asUint8List(),
        )
      : null;
  return _InvoiceSheet(template, invoice, data, art, paper).build();
}

class _InvoiceSheet {
  _InvoiceSheet(
    this.template,
    this.data,
    Map<String, ByteData> files,
    this.art,
    this.format,
  ) : regular = pw.Font.ttf(files['Manrope-Regular']!),
      bold = pw.Font.ttf(files['Manrope-SemiBold']!),
      display = pw.Font.ttf(files['Manrope-ExtraBold']!),
      condensed = pw.Font.ttf(files['BarlowCondensed-SemiBold']!);
  final InvoicePaper format;
  final pw.MemoryImage? art;
  final InvoiceTemplate template;
  final Map<String, dynamic> data;
  final pw.Font regular, bold, condensed, display;
  final serif = pw.Font.timesBold(), mono = pw.Font.courierBold();
  String get id => template.id;
  String v(String key) => _s(data[key]);
  String setting(String key) {
    final settings = data['settings'];
    return settings is Map ? _s(settings[key]) : '';
  }

  late final pw.MemoryImage? _logo = setting('logo_base64').isEmpty
      ? null
      : pw.MemoryImage(base64Decode(setting('logo_base64')));
  bool get hasLogo => _logo != null;

  pw.Widget _logoMark({double maxWidth = 85, double maxHeight = 34}) {
    final image = _logo;
    if (image == null) return pw.SizedBox();
    // Preserve the uploaded artwork's aspect ratio on both narrow and square marks.
    final scale = math.min(maxWidth / image.width!, maxHeight / image.height!);
    return pw.Image(
      image,
      width: image.width! * scale,
      height: image.height! * scale,
      fit: pw.BoxFit.contain,
    );
  }

  bool get night => format == InvoicePaper.a4 && id == 'ribbon';
  late final PdfColor accent = format.isReceipt
      ? PdfColors.black
      : PdfColor.fromInt(template.printAccent(setting('accent_color')));
  PdfColor get ink => PdfColor.fromHex(night ? '#F8F7F5' : '#1E2224');
  PdfColor get muted => PdfColor.fromHex(night ? '#C8C8CE' : '#495159');
  PdfColor get rule => PdfColor.fromHex(night ? '#38393D' : '#D8D9D6');
  PdfColor get tint => PdfColor.fromHex(night ? '#1B1B1D' : '#F0F1EE');
  static final paper = PdfColors.white;
  double get left => id == 'dispatch' ? 49 : 33;
  bool get compact => const {
    'ledger',
    'carbon',
    'dispatch',
    'offset',
    'blueprint',
  }.contains(id);
  bool get isReturn => _yes(data['is_return']);
  int get precision => (int.tryParse(v('precision')) ?? 2).clamp(0, 12);
  String get title => isReturn ? 'Credit note' : 'Invoice';
  String get seller =>
      v('seller_name').isEmpty ? v('company') : v('seller_name');
  String get buyer =>
      v('customer_name').isEmpty ? v('customer') : v('customer_name');
  String get currency => v('currency');
  String get state => _yes(data['source_copy'])
      ? (v('docstatus') == '2' ? 'Cancelled original copy' : 'Original copy')
      : v('docstatus') == '2'
      ? 'Cancelled'
      : v('docstatus') == '0'
      ? 'Draft'
      : v('status');
  String amount(dynamic raw, {String? unit, int? places, bool symbol = true}) {
    if (_s(raw).isEmpty) return '—';
    final c = unit ?? currency;
    final n = formatInvoiceNumber(
      raw,
      places: places ?? precision,
      indian: c == 'INR',
    );
    return symbol
        ? '${c == 'INR'
              ? '₹'
              : c == 'USD'
              ? r'$'
              : c == 'EUR'
              ? '€'
              : c == 'GBP'
              ? '£'
              : '$c '}$n'
        : n;
  }

  pw.Widget txt(
    String text, {
    double size = 9,
    pw.Font? font,
    PdfColor? color,
    pw.TextAlign? align,
    double spacing = 0,
  }) {
    // Add a line-breaking opportunity to long unbroken user references.
    final display = text.replaceAllMapped(
      RegExp(r'[^\s-]{44,}'),
      (m) => _chunks(m.group(0)!, 40).join('\n'),
    );
    return pw.Text(
      display,
      textAlign: align,
      style: pw.TextStyle(
        font: font ?? regular,
        fontFallback: [regular],
        fontSize: size,
        letterSpacing: spacing,
        color: color ?? ink,
        lineSpacing: 1.2,
      ),
    );
  }

  pw.Widget label(String text, {PdfColor? color}) => txt(
    text.toUpperCase(),
    size: 7,
    font: bold,
    color: night && color == accent
        ? PdfColor.fromHex('#B6C8FF')
        : color ?? muted,
    spacing: 1.05,
  );

  Future<Uint8List> build() async {
    final doc = pw.Document(
      title: '$title ${v('name')}',
      author: seller,
      subject: template.name,
      creator: 'ERP Workspace',
    );
    if (format != InvoicePaper.a4) {
      doc.addPage(_compactPage());
      return doc.save();
    }
    final page = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(left, 30, 36, 28),
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [regular],
      ),
      buildBackground: (c) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.CustomPaint(
                painter: (canvas, size) => _stationery(c, canvas, size),
              ),
            ),
          ],
        ),
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageTheme: page,
        maxPages: 10000,
        header: (c) => c.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: txt(seller, size: 9, font: bold)),
                    txt('$title  /  ${v('name')}', size: 9, color: muted),
                  ],
                ),
              ),
        footer: (c) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Column(
            children: [
              if (_footerTerms) ...[
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: label('Terms', color: accent),
                ),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: txt(v('terms'), size: 8.2, color: muted),
                ),
                pw.SizedBox(height: 11),
              ],
              pw.Divider(color: rule, thickness: .6, height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Flexible(
                    child: txt(v('name'), size: 7, font: bold, color: muted),
                  ),
                  txt(
                    '${c.pageNumber} / ${c.pagesCount}',
                    size: 7,
                    color: muted,
                  ),
                ],
              ),
            ],
          ),
        ),
        build: (c) => [
          ..._frontMatter(),
          _table(),
          pw.SizedBox(height: 12),
          ..._summary(),
          ..._paymentDetails(),
          ..._notes(),
        ],
      ),
    );
    return doc.save();
  }

  bool get _footerTerms =>
      format == InvoicePaper.a4 &&
      const {'canopy', 'ribbon', 'grove', 'folio', 'cobalt'}.contains(id) &&
      v('terms').isNotEmpty &&
      v('terms').length <= 170;
  pw.Widget _details({bool inMast = false}) {
    final pairs = <MapEntry<String, String>>[
      MapEntry('Issued', _date(v('posting_date'))),
      if (v('due_date').isNotEmpty) MapEntry('Due', _date(v('due_date'))),
      if (v('po_no').isNotEmpty) MapEntry('Purchase order', v('po_no')),
      if (v('po_date').isNotEmpty) MapEntry('Order date', _date(v('po_date'))),
      if (state.isNotEmpty) MapEntry('Status', state),
    ];
    return pw.Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final p in pairs)
          pw.SizedBox(
            width: 108,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                label(p.key, color: inMast ? paper : null),
                pw.SizedBox(height: 2),
                txt(p.value, size: 10, font: bold, color: inMast ? paper : ink),
              ],
            ),
          ),
      ],
    );
  }

  (String, List<String>) _itemDescription(
    Map<String, dynamic> item, {
    bool separateCode = false,
  }) {
    final name = _s(item['item_name']).isEmpty && !_yes(data['source_copy'])
        ? _s(item['item_code'])
        : _s(item['item_name']);
    final brief = <String>[
      if (!separateCode &&
          _s(item['item_code']).isNotEmpty &&
          _s(item['item_code']) != name)
        _s(item['item_code']),
      if (_s(item['description']).isNotEmpty && _s(item['description']) != name)
        _s(item['description']),
    ];
    if (_nonzero(item['discount_amount']) ||
        _nonzero(item['discount_percentage'])) {
      final rate = _nonzero(item['discount_percentage'])
          ? '  ${formatInvoiceNumber(item['discount_percentage'])}%'
          : '';
      brief.add(
        'Line discount$rate${_nonzero(item['discount_amount']) ? '  ${amount(item['discount_amount'])}' : ''}',
      );
    }
    for (final tax in _rows(item['taxes'])) {
      brief.add(
        '${_s(tax['label'])}${_s(tax['rate']).isEmpty ? '' : '  ${formatInvoiceNumber(tax['rate'])}%'}${_s(tax['amount']).isEmpty ? '' : '  ${amount(tax['amount'], unit: _s(tax['currency']).isEmpty ? currency : _s(tax['currency']))}'}',
      );
    }
    return (name, brief);
  }

  // Rates can carry more decimal places than a rounded payable amount.
  String itemRate(dynamic rate) {
    final value = _s(rate);
    final fraction = value.split('.');
    final digits = fraction.length == 2
        ? fraction.last.replaceFirst(RegExp(r'0+$'), '').length
        : 0;
    return amount(rate, places: math.max(precision, digits));
  }

  pw.Widget _table() {
    final items = _rows(data['items']);
    final hsn = items.any((r) => _s(r['hsn_sac']).isNotEmpty);
    final mode = switch (id) {
      'blueprint' || 'carbon' => 'grid',
      'grove' || 'saffron' || 'ledger' => 'band',
      'offset' || 'cobalt' || 'mariner' || 'dispatch' => 'strong',
      _ => 'rule',
    };
    final separateCode = id == 'blueprint' || id == 'carbon';
    final qtyFirst = id == 'dispatch' || id == 'offset';
    const nameKey = 'Item / description', hsnKey = 'HSN / SAC';
    final qtyKey =
        _yes(data['source_copy']) && v('source_quantity_label').isNotEmpty
        ? v('source_quantity_label')
        : 'Qty / UOM';
    final rateKey =
        _yes(data['source_copy']) && v('source_rate_label').isNotEmpty
        ? v('source_rate_label')
        : 'Rate';
    final heads = [
      if (qtyFirst) qtyKey,
      if (separateCode) 'Code',
      nameKey,
      if (hsn) hsnKey,
      if (!qtyFirst) qtyKey,
      rateKey,
      'Amount',
    ];
    final sizes = {
      nameKey: 3.2,
      qtyKey: 1.0,
      hsnKey: .88,
      'Code': .95,
      rateKey: 1.12,
      'Amount': 1.28,
    };
    final widths = {
      for (final (i, key) in heads.indexed) i: pw.FlexColumnWidth(sizes[key]!),
    };
    bool numeric(String key) =>
        key == qtyKey || key == rateKey || key == 'Amount';
    pw.Widget cell(pw.Widget child, {bool right = false}) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: compact ? 5 : 6,
      ),
      child: pw.Align(
        alignment: right ? pw.Alignment.topRight : pw.Alignment.topLeft,
        child: child,
      ),
    );
    final strong = mode == 'strong' || mode == 'grid';
    final grid = mode == 'grid';
    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(
          color: strong
              ? accent
              : mode == 'band'
              ? tint
              : null,
          border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1)),
        ),
        children: [
          for (final head in heads)
            cell(
              txt(
                head.toUpperCase(),
                size: 7.4,
                font: bold,
                color: strong
                    ? paper
                    : night
                    ? muted
                    : accent,
                spacing: .35,
              ),
              right: numeric(head),
            ),
        ],
      ),
    ];
    for (final (index, item) in items.indexed) {
      final (name, brief) = _itemDescription(item, separateCode: separateCode);
      // Spanning tables break between rows. Split very long individual descriptions
      // into continuation rows so no field can be taller than an entire A4 page.
      final nameLines = _chunks(name, 48);
      final detailLines = _chunks(brief.join(' · '), 60);
      final textLines = [
        for (final line in nameLines) (line, true),
        for (final line in detailLines) (line, false),
      ];
      final sections = math.max(1, (textLines.length / 10).ceil());
      for (var part = 0; part < sections; part++) {
        final text = textLines.skip(part * 10).take(10);
        final values = {
          'Code': _s(item['item_code']),
          hsnKey: _s(item['hsn_sac']),
          qtyKey:
              '${formatInvoiceNumber(item['qty'], indian: currency == 'INR')} ${_s(item['uom'])}'
                  .trim(),
          rateKey: itemRate(item['rate']),
          'Amount': amount(item['amount']),
        };
        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: mode == 'band' && index.isOdd ? tint : null,
              border: pw.Border(bottom: pw.BorderSide(color: rule, width: .5)),
            ),
            children: [
              for (final key in heads)
                if (key == nameKey)
                  cell(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (final (line, strongText) in text)
                          txt(
                            line,
                            size: strongText ? 10.2 : 8.2,
                            font: strongText ? bold : regular,
                            color: strongText ? ink : muted,
                          ),
                      ],
                    ),
                  )
                else
                  cell(
                    part == 0
                        ? txt(
                            values[key]!,
                            size: 8.1,
                            font: key == 'Amount' ? bold : regular,
                            align: numeric(key)
                                ? pw.TextAlign.right
                                : pw.TextAlign.left,
                          )
                        : pw.SizedBox(),
                    right: numeric(key),
                  ),
            ],
          ),
        );
      }
    }
    return pw.Table(
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      border: grid ? pw.TableBorder.all(color: rule, width: .45) : null,
      children: rows,
    );
  }

  List<pw.Widget> _summary() {
    final actualTaxes = _rows(data['taxes']);
    final lines = <MapEntry<String, String>>[
      if (v('total').isNotEmpty && _nonzero(v('discount_amount')))
        MapEntry('Subtotal', amount(data['total'])),
      if (_nonzero(v('discount_amount')))
        MapEntry(
          'Additional discount${_nonzero(v('additional_discount_percentage')) ? ' (${formatInvoiceNumber(data['additional_discount_percentage'])}%)' : ''}',
          amount(data['discount_amount']),
        ),
      if (v('net_total').isNotEmpty)
        MapEntry(
          _yes(data['source_copy']) && v('source_net_total_label').isNotEmpty
              ? v('source_net_total_label')
              : 'Net amount',
          amount(data['net_total']),
        ),
      for (final tax in actualTaxes)
        MapEntry(
          '${_s(tax['label']).isEmpty ? _s(tax['account']) : _s(tax['label'])}${_s(tax['rate']).isEmpty ? '' : '  ${formatInvoiceNumber(tax['rate'])}%'}${_yes(tax['included_in_price']) ? ' (included)' : ''}',
          amount(tax['amount']),
        ),
      if (actualTaxes.isEmpty && _nonzero(v('total_taxes_and_charges')))
        MapEntry('Taxes and charges', amount(data['total_taxes_and_charges'])),
    ];
    final rounded =
        !_yes(data['disable_rounded_total']) &&
        _nonzero(v('rounded_total')) &&
        _nonzero(v('rounding_adjustment'));
    if (rounded) {
      lines.addAll([
        MapEntry('Grand total', amount(data['grand_total'])),
        MapEntry('Rounding adjustment', amount(data['rounding_adjustment'])),
      ]);
    }
    pw.Widget sumLine(String key, String value, {bool large = false}) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 4,
          child: txt(
            key,
            size: large ? 12 : 8.6,
            font: large ? bold : regular,
            color: large ? paper : muted,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Flexible(
          flex: 6,
          child: pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            child: txt(
              value,
              size: large ? 18 : 9.2,
              font: bold,
              color: large ? paper : ink,
              align: pw.TextAlign.right,
            ),
          ),
        ),
      ],
    );
    pw.Widget positioned(pw.Widget w) => pw.Align(
      alignment: const {'folio', 'pearl', 'offset'}.contains(id)
          ? pw.Alignment.centerLeft
          : pw.Alignment.centerRight,
      child: pw.Container(
        width: const {'dispatch', 'mariner', 'ledger'}.contains(id) ? 275 : 249,
        child: w,
      ),
    );
    return [
      for (final line in lines)
        positioned(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: sumLine(line.key, line.value),
          ),
        ),
      pw.SizedBox(height: 4),
      positioned(
        pw.Container(
          color: accent,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: sumLine(
            rounded
                ? 'Rounded total'
                : isReturn
                ? 'Credit total'
                : 'Invoice total',
            amount(rounded ? data['rounded_total'] : data['grand_total']),
            large: true,
          ),
        ),
      ),
      if (v('outstanding_amount').isNotEmpty) ...[
        pw.SizedBox(height: 5),
        positioned(
          sumLine(
            'Outstanding',
            amount(
              data['outstanding_amount'],
              unit: v('outstanding_currency').isEmpty
                  ? currency
                  : v('outstanding_currency'),
              places: int.tryParse(v('outstanding_precision')),
            ),
          ),
        ),
      ],
    ];
  }

  bool get _collectible =>
      !_yes(data['source_copy']) &&
      v('docstatus') == '1' &&
      !isReturn &&
      RegExp(r'^\+?\d+(?:\.\d+)?$').hasMatch(v('outstanding_amount')) &&
      _nonzero(v('outstanding_amount'));

  String get _upiRequest {
    if (!_collectible ||
        currency != 'INR' ||
        v('outstanding_currency') != 'INR') {
      return '';
    }
    final request = v('upi_uri');
    if (request.isEmpty) return '';
    final uri = Uri.tryParse(request);
    if (uri == null ||
        uri.scheme != 'upi' ||
        uri.authority != 'pay' ||
        uri.path.isNotEmpty ||
        uri.hasFragment) {
      return '';
    }
    // Use the exact server-issued payload for both print and the tap target.
    return request;
  }

  pw.Widget _qrCode(String payload, {required double size}) => pw.BarcodeWidget(
    barcode: Barcode.qrCode(),
    data: payload,
    drawText: false,
    width: size,
    height: size,
    padding: const pw.EdgeInsets.all(12),
    backgroundColor: paper,
  );

  List<pw.Widget> _paymentDetails() {
    final fields = {
      'Bank': setting('bank_name'),
      'Account holder': setting('account_holder'),
      'Account number': setting('account_number'),
      'IFSC': setting('ifsc'),
    }..removeWhere((_, value) => value.isEmpty);
    final upi = _upiRequest;
    if (fields.isEmpty && upi.isEmpty) return [];

    final payee = setting('upi_name');
    pw.Widget details(String title, Map<String, String> entries) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        label(title, color: accent),
        pw.SizedBox(height: 5),
        for (final entry in entries.entries)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(font: regular, fontSize: 8.4, color: ink),
                children: [
                  pw.TextSpan(
                    text: '${entry.key}  ',
                    style: pw.TextStyle(color: muted),
                  ),
                  pw.TextSpan(
                    text: entry.value.replaceAllMapped(
                      RegExp(r'\S{23,}'),
                      (match) => _chunks(match.group(0)!, 22).join('\n'),
                    ),
                    style: pw.TextStyle(font: bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (format.isReceipt) {
      return [
        pw.SizedBox(height: 8),
        if (fields.isNotEmpty)
          details(_collectible ? 'Bank transfer' : 'Bank details', fields),
        if (upi.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          label('Pay by UPI'),
          if (payee.isNotEmpty) txt(payee),
          pw.UrlLink(destination: upi, child: _qrCode(upi, size: 100)),
        ],
      ];
    }
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14),
        child: pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: rule, width: .7)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (fields.isNotEmpty)
                pw.Expanded(
                  flex: 6,
                  child: details(
                    _collectible ? 'Bank transfer' : 'Bank details',
                    fields,
                  ),
                ),
              if (fields.isNotEmpty && upi.isNotEmpty) pw.SizedBox(width: 14),
              if (upi.isNotEmpty) ...[
                pw.Expanded(
                  flex: 5,
                  child: details('Pay by UPI', {
                    if (payee.isNotEmpty) 'Payee': payee,
                    if (setting('upi_id').isNotEmpty)
                      'UPI ID': setting('upi_id'),
                    'Amount': amount(data['outstanding_amount']),
                  }),
                ),
                pw.SizedBox(width: 5),
                pw.UrlLink(destination: upi, child: _qrCode(upi, size: 88)),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  List<pw.Widget> _notes() {
    final summary = <String, String>{
      if (v('in_words').isNotEmpty) 'Amount in words': v('in_words'),
      if (v('place_of_supply').isNotEmpty)
        'Place of supply': v('place_of_supply'),
    };
    final transporter = v('transporter_name').isEmpty
        ? v('transporter')
        : v('transporter_name');
    final transport = <MapEntry<String, String>>[
      if (v('shipping_rule').isNotEmpty)
        MapEntry('Shipping rule', v('shipping_rule')),
      if (v('incoterm').isNotEmpty) MapEntry('Incoterm', v('incoterm')),
      if (v('named_place').isNotEmpty)
        MapEntry('Named place', v('named_place')),
      if (v('mode_of_transport').isNotEmpty)
        MapEntry('Mode of transport', v('mode_of_transport')),
      if (transporter.isNotEmpty) MapEntry('Transporter', transporter),
      if (v('vehicle_no').isNotEmpty)
        MapEntry('Vehicle number', v('vehicle_no')),
      if (v('lr_no').isNotEmpty) MapEntry('Transport receipt', v('lr_no')),
      if (v('lr_date').isNotEmpty)
        MapEntry('Transport receipt date', _date(v('lr_date'))),
    ];
    final notes = <MapEntry<String, String>>[
      if (v('dispatch_address').isNotEmpty)
        MapEntry('Dispatch from', v('dispatch_address')),
      if (v('shipping_address').isNotEmpty &&
          v('shipping_address') != v('billing_address'))
        MapEntry('Ship to', v('shipping_address')),
      if (v('return_against').isNotEmpty)
        MapEntry('Return against', v('return_against')),
      if (v('amended_from').isNotEmpty) MapEntry('Amends', v('amended_from')),
      for (final delivery in _rows(data['delivery_notes']))
        if (_s(delivery['name']).isNotEmpty)
          MapEntry(
            'Delivery note',
            [
              _s(delivery['name']),
              if (_s(delivery['posting_date']).isNotEmpty)
                'Dispatch posted ${_date(delivery['posting_date'])}',
              if (_s(delivery['dispatch_address']).isNotEmpty &&
                  _s(delivery['dispatch_address']) != v('dispatch_address'))
                'Dispatch from ${_s(delivery['dispatch_address'])}',
              if (_s(delivery['mode_of_transport']).isNotEmpty)
                'Transport mode ${_s(delivery['mode_of_transport'])}',
              if (_s(delivery['transporter_name']).isNotEmpty)
                'Transporter ${_s(delivery['transporter_name'])}'
              else if (_s(delivery['transporter']).isNotEmpty)
                'Transporter ${_s(delivery['transporter'])}',
              if (_s(delivery['vehicle_no']).isNotEmpty)
                'Vehicle ${_s(delivery['vehicle_no'])}',
              if (_s(delivery['lr_no']).isNotEmpty)
                'Transport receipt ${_s(delivery['lr_no'])}',
              if (_s(delivery['lr_date']).isNotEmpty)
                'Receipt date ${_date(delivery['lr_date'])}',
            ].join(' · '),
          ),
      if (v('irn').isNotEmpty) MapEntry('IRN', v('irn')),
      if (v('acknowledgement_number').isNotEmpty)
        MapEntry('Acknowledgement', v('acknowledgement_number')),
      if (v('acknowledgement_date').isNotEmpty)
        MapEntry('Acknowledged on', v('acknowledgement_date')),
      if (v('paid_amount').isNotEmpty && _nonzero(v('paid_amount')))
        MapEntry('Paid amount', amount(data['paid_amount'])),
      for (final p in _rows(data['payments']))
        MapEntry('Payment · ${_s(p['mode_of_payment'])}', amount(p['amount'])),
      for (final p in _rows(data['payment_schedule']))
        MapEntry(
          'Payment due ${_date(p['due_date'])}',
          amount(p['payment_amount']),
        ),
      if (v('terms').isNotEmpty && !_footerTerms) MapEntry('Terms', v('terms')),
    ];
    final qr = v('signed_qr_code');
    return [
      if (summary.isNotEmpty || notes.isNotEmpty || qr.isNotEmpty)
        pw.SizedBox(height: 8),
      if (summary.isNotEmpty)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final entry in summary.entries)
              pw.Expanded(
                flex: entry.key == 'Amount in words' ? 2 : 1,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 8, bottom: 5),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      style: pw.TextStyle(
                        font: regular,
                        color: muted,
                        fontSize: 8.2,
                      ),
                      children: [
                        pw.TextSpan(
                          text: '${entry.key}  ',
                          style: pw.TextStyle(font: bold, color: ink),
                        ),
                        pw.TextSpan(text: entry.value),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      if (transport.isNotEmpty) ...[
        pw.Wrap(
          spacing: 12,
          runSpacing: 3,
          children: [
            for (final entry in transport)
              pw.RichText(
                text: pw.TextSpan(
                  style: pw.TextStyle(font: regular, fontSize: 8.2, color: ink),
                  children: [
                    pw.TextSpan(
                      text: '${entry.key}  ',
                      style: pw.TextStyle(font: bold),
                    ),
                    pw.TextSpan(text: entry.value),
                  ],
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
      ],
      for (final n in notes) ...[
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            label(n.key, color: accent),
            txt(_chunks(n.value, 112).first, size: 8.2, color: muted),
          ],
        ),
        for (final line in _chunks(n.value, 112).skip(1))
          txt(line, size: 8.2, color: muted),
        pw.SizedBox(height: 5),
      ],
      if (qr.isNotEmpty)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            label('GST e-invoice verification', color: accent),
            pw.SizedBox(height: 4),
            _qrCode(qr, size: 106),
          ],
        ),
      if (!_yes(data['source_copy'])) ...[
        if (setting('signatory_name').isNotEmpty) ...[
          pw.SizedBox(height: 9),
          label('Authorised signatory'),
          txt(setting('signatory_name'), font: bold),
        ],
        if (setting('print_footer').isNotEmpty) ...[
          pw.SizedBox(height: 6),
          txt(setting('print_footer'), size: 8, color: muted),
        ],
      ],
    ];
  }
}
