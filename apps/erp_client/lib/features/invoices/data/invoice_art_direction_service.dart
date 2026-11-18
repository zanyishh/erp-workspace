part of 'invoice_pdf_service.dart';

const _materialStyles = {
  'canopy',
  'ribbon',
  'terracotta',
  'grove',
  'seam',
  'mariner',
  'pearl',
};

extension _InvoiceArtDirection on _InvoiceSheet {
  PdfColor _color(String hex) => PdfColor.fromHex(hex);

  pw.Widget _brand(PdfColor color, {bool centered = false}) => pw.Row(
    mainAxisAlignment: centered
        ? pw.MainAxisAlignment.center
        : pw.MainAxisAlignment.start,
    mainAxisSize: centered ? pw.MainAxisSize.max : pw.MainAxisSize.min,
    children: [
      if (hasLogo) ...[
        _logoMark(maxWidth: 66, maxHeight: 27),
        pw.SizedBox(width: 8),
      ],
      pw.Flexible(
        child: txt(seller, font: bold, size: 13, color: color),
      ),
    ],
  );

  pw.Widget _title(
    double size, {
    pw.Font? face,
    PdfColor? color,
    bool caps = false,
  }) => pw.FittedBox(
    fit: pw.BoxFit.scaleDown,
    alignment: pw.Alignment.centerLeft,
    child: txt(
      caps ? title.toUpperCase() : title,
      size: size,
      font: face ?? display,
      color: color ?? ink,
      spacing: -size * .045,
    ),
  );

  pw.Widget _ref(PdfColor color) =>
      txt(v('name'), size: 9.6, font: bold, color: color);
  pw.Widget _photo(double h, {pw.Alignment align = pw.Alignment.center}) =>
      pw.Container(
        height: h,
        decoration: pw.BoxDecoration(
          image: pw.DecorationImage(image: art!, alignment: align),
        ),
      );
  pw.Widget _pair(bool recipient, {PdfColor? color, String? heading}) {
    final fg = color ?? ink;
    final address = v(recipient ? 'billing_address' : 'company_address');
    final gst = v(recipient ? 'customer_gstin' : 'company_gstin');
    final taxId = v(recipient ? 'tax_id' : 'company_tax_id');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        label(
          heading ?? (recipient ? 'Bill to' : 'From'),
          color: color ?? accent,
        ),
        pw.SizedBox(height: 3),
        txt(recipient ? buyer : seller, font: bold, size: 12.5, color: fg),
        if (address.isNotEmpty) txt(address, size: 8.8, color: color ?? muted),
        if (gst.isNotEmpty)
          txt('GSTIN  $gst', size: 8.2, font: bold, color: fg),
        if (taxId.isNotEmpty && taxId.toUpperCase() != gst.toUpperCase())
          txt('Tax ID  $taxId', size: 8.2, font: bold, color: fg),
      ],
    );
  }

  pw.Widget _addresses({PdfColor? color, bool buyerFirst = false}) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: _pair(buyerFirst, color: color)),
      pw.SizedBox(width: 18),
      pw.Expanded(child: _pair(!buyerFirst, color: color)),
    ],
  );

  pw.Widget _identityLine(PdfColor color) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Expanded(child: _brand(color)),
      pw.SizedBox(width: 12),
      pw.Flexible(
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _ref(color),
        ),
      ),
    ],
  );

  pw.Widget _panel(
    pw.Widget content, {
    required PdfColor color,
    double inset = 16,
    double radius = 0,
    pw.Widget? rear,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      color: color,
      borderRadius: pw.BorderRadius.circular(radius),
    ),
    child: pw.Stack(
      children: [
        if (rear != null) pw.Positioned.fill(child: rear),
        pw.Padding(padding: pw.EdgeInsets.all(inset), child: content),
      ],
    ),
  );

  List<pw.Widget> _frontMatter() {
    // All party blocks are in the flow so a multi-line address grows the design.
    final parts = <pw.Widget>[];
    switch (id) {
      case 'canopy':
        parts.add(
          _panel(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _identityLine(_InvoiceSheet.paper),
                pw.SizedBox(height: 11),
                _title(73, color: _InvoiceSheet.paper),
                pw.SizedBox(height: 10),
                _addresses(color: _InvoiceSheet.paper),
              ],
            ),
            color: _color('#201528'),
            inset: 18,
            radius: 10,
            rear: pw.ClipRRect(
              horizontalRadius: 10,
              verticalRadius: 10,
              child: pw.Opacity(
                opacity: .64,
                child: pw.Image(art!, fit: pw.BoxFit.cover),
              ),
            ),
          ),
        );
      case 'ribbon':
        parts.addAll([
          // The studio image is full-bleed above the document's live text.
          pw.SizedBox(height: 89),
          _identityLine(_InvoiceSheet.paper),
          pw.SizedBox(height: 10),
          _title(66, color: _InvoiceSheet.paper, caps: true),
          pw.SizedBox(height: 11),
          _addresses(),
        ]);
      case 'offset':
        final charcoal = _color('#262627');
        parts.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 4,
                child: _panel(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _brand(_InvoiceSheet.paper),
                      pw.SizedBox(height: 19),
                      _pair(true, color: _InvoiceSheet.paper),
                    ],
                  ),
                  color: charcoal,
                  inset: 15,
                ),
              ),
              pw.SizedBox(width: 21),
              pw.Expanded(
                flex: 6,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _title(52, caps: true),
                    pw.SizedBox(height: 3),
                    _ref(ink),
                    pw.Divider(height: 13, thickness: 1.2, color: ink),
                    _pair(false),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'cobalt':
        parts.add(
          _panel(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _identityLine(_InvoiceSheet.paper),
                pw.SizedBox(height: 10),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: _title(59, caps: true, color: _InvoiceSheet.paper),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      flex: 3,
                      child: _pair(true, color: _InvoiceSheet.paper),
                    ),
                  ],
                ),
              ],
            ),
            color: _color('#34498D'),
            radius: 18,
            inset: 14,
            rear: pw.ClipRRect(
              horizontalRadius: 18,
              verticalRadius: 18,
              child: _cobaltFolds(),
            ),
          ),
        );
        parts.addAll([pw.SizedBox(height: 8), _pair(false)]);
      case 'folio':
        parts.addAll([
          _brand(accent, centered: true),
          pw.SizedBox(height: 3),
          pw.Center(
            child: _title(81, face: serif, color: accent),
          ),
          pw.Center(child: _ref(accent)),
          pw.Divider(height: 15, color: accent),
          _addresses(buyerFirst: true),
        ]);
      case 'terracotta':
      case 'grove':
      case 'mariner':
      case 'pearl':
        parts.addAll([
          _materialHeader(),
          pw.SizedBox(height: 14),
          _addresses(buyerFirst: id == 'terracotta' || id == 'mariner'),
        ]);
      case 'seam':
        parts.addAll([
          _identityLine(accent),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: _title(66, face: serif, color: accent),
              ),
              pw.SizedBox(width: 18),
              pw.Expanded(flex: 2, child: _photo(58)),
            ],
          ),
          pw.Divider(height: 14, color: accent),
          _addresses(buyerFirst: true),
        ]);
      case 'ledger':
        parts.addAll([
          _identityLine(ink),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 3),
            color: accent,
            child: _title(
              56,
              face: condensed,
              caps: true,
              color: _InvoiceSheet.paper,
            ),
          ),
          pw.SizedBox(height: 12),
          _addresses(),
        ]);
      case 'blueprint':
        parts.addAll([
          _identityLine(accent),
          pw.SizedBox(height: 12),
          pw.SizedBox(
            height: 76,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: _title(63, face: condensed, caps: true, color: accent),
                ),
                pw.SizedBox(width: 15),
                _drawingDetail(),
              ],
            ),
          ),
          pw.Divider(height: 13, color: accent),
          _addresses(),
        ]);
      case 'carbon':
        parts.addAll([
          _identityLine(ink),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(child: _title(55, face: mono, caps: true)),
              pw.SizedBox(width: 12),
              _serialStamp(),
            ],
          ),
          pw.Divider(height: 15, color: ink),
          _addresses(),
        ]);
      case 'saffron':
        parts.addAll([
          _identityLine(ink),
          pw.SizedBox(height: 11),
          _panel(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                label(
                  isReturn ? 'Credit note total' : 'Invoice total',
                  color: ink,
                ),
                pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: txt(
                    amount(data['grand_total']),
                    font: bold,
                    size: 46,
                    color: ink,
                    spacing: -1.8,
                  ),
                ),
              ],
            ),
            color: _color('#F6BF44'),
            inset: 13,
          ),
          pw.SizedBox(height: 14),
          _addresses(buyerFirst: true),
        ]);
      case 'dispatch':
        parts.addAll([
          _identityLine(accent),
          pw.SizedBox(height: 12),
          pw.SizedBox(
            height: 76,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(child: _title(65, face: condensed, caps: true)),
                _dispatchArrow(),
              ],
            ),
          ),
          pw.Divider(height: 12, thickness: 2, color: ink),
          _addresses(buyerFirst: true),
        ]);
    }
    parts.addAll([
      pw.SizedBox(height: 10),
      _details(),
      pw.SizedBox(height: 14),
    ]);
    return parts;
  }

  pw.Widget _materialHeader() {
    final foreground = id == 'grove' || id == 'mariner'
        ? _InvoiceSheet.paper
        : ink;
    if (id == 'pearl') {
      return pw.Column(
        children: [
          _brand(accent, centered: true),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _photo(55, align: pw.Alignment.topLeft)),
              pw.SizedBox(width: 15),
              _title(56, face: serif, color: accent),
              pw.SizedBox(width: 15),
              pw.Expanded(child: _photo(55, align: pw.Alignment.bottomRight)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Center(child: _ref(accent)),
        ],
      );
    }
    final slab = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: id == 'grove'
          ? _color('#23362A')
          : id == 'mariner'
          ? _color('#0A3043')
          : _color('#F0D7C8'),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _brand(foreground),
          pw.SizedBox(height: 6),
          _title(
            id == 'mariner' ? 57 : 64,
            face: id == 'mariner' ? condensed : serif,
            caps: id == 'mariner',
            color: foreground,
          ),
          _ref(foreground),
        ],
      ),
    );
    if (id == 'grove') {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 45, child: pw.Image(art!, fit: pw.BoxFit.cover)),
          slab,
        ],
      );
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (id == 'terracotta') ...[
          pw.Expanded(flex: 3, child: _photo(126)),
          pw.SizedBox(width: 5),
        ],
        pw.Expanded(flex: 5, child: slab),
        if (id == 'mariner') ...[
          pw.SizedBox(width: 4),
          pw.Expanded(flex: 4, child: _photo(127)),
        ],
      ],
    );
  }

  pw.Widget _cobaltFolds() => pw.CustomPaint(
    painter: (g, s) {
      final w = s.x, h = s.y;
      g
        ..setFillColor(_color('#4C62A3'))
        ..moveTo(w * .30, h)
        ..curveTo(w * .56, h * .73, w * .57, h * .08, w, h * .31)
        ..lineTo(w, h)
        ..closePath()
        ..fillPath();
      g
        ..setFillColor(_color('#576EAD'))
        ..moveTo(w * .58, h)
        ..curveTo(w * .80, h * .60, w * .86, h * .68, w, h * .8)
        ..lineTo(w, h)
        ..closePath()
        ..fillPath();
    },
  );

  pw.Widget _drawingDetail() => pw.CustomPaint(
    size: const PdfPoint(92, 52),
    painter: (g, s) {
      g
        ..setStrokeColor(_color('#598A92'))
        ..setLineWidth(.65);
      for (var n = 0; n < 4; n++) {
        g
          ..drawEllipse(49, 26, 21 - n * 3.7, 20 - n * 3.7)
          ..strokePath();
      }
      g
        ..drawLine(1, 26, 90, 26)
        ..drawLine(49, 1, 49, 51)
        ..strokePath();
      g
        ..setLineWidth(1.2)
        ..drawLine(16, 3, 82, 48)
        ..strokePath();
    },
  );

  pw.Widget _serialStamp() => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: ink)),
    child: txt(_date(v('posting_date')), font: mono, size: 10, color: ink),
  );

  pw.Widget _dispatchArrow() => pw.CustomPaint(
    size: const PdfPoint(56, 39),
    painter: (g, s) {
      g
        ..setStrokeColor(accent)
        ..setLineWidth(6)
        ..drawLine(3, 2, 43, 32)
        ..drawLine(42, 31, 22, 30)
        ..drawLine(43, 33, 43, 13)
        ..strokePath();
    },
  );

  void _stationery(pw.Context c, PdfGraphics g, PdfPoint s) {
    final w = s.x, h = s.y;
    void rect(double x, double y, double width, double height, PdfColor color) {
      g
        ..setFillColor(color)
        ..drawRect(x, h - y - height, width, height)
        ..fillPath();
    }

    void ruleAt(
      double x,
      double y,
      double x2,
      double y2,
      PdfColor color, [
      double weight = .65,
    ]) {
      g
        ..setStrokeColor(color)
        ..setLineWidth(weight)
        ..drawLine(x, h - y, x2, h - y2)
        ..strokePath();
    }

    final background = switch (id) {
      'ribbon' => '#08090B',
      'offset' => '#EEEFED',
      'folio' => '#FFFDF8',
      'terracotta' => '#FFFBF7',
      'pearl' => '#FFFDFA',
      'saffron' => '#FFFCF4',
      'blueprint' => '#F1F7F6',
      'dispatch' => '#FCF7EB',
      'seam' => '#FFF9F5',
      'carbon' => '#FAFAF7',
      _ => '#FFFFFF',
    };
    rect(0, 0, w, h, _color(background));
    if (id == 'dispatch') {
      rect(0, 0, 29, h, accent);
      for (var j = 24.0; j < h; j += 15) {
        ruleAt(11, j, 19, j, _color('#F4EADA'), .75);
      }
    }
    if (c.pageNumber != 1) {
      rect(left, 16, w - left - 33, 1.5, accent);
      return;
    }
    if (id == 'ribbon') {
      pw.DecorationImage(image: art!).paint(c, PdfRect(0, h - 112, w, 112));
    } else if (id == 'folio') {
      ruleAt(33, 15, w - 33, 15, accent, 2);
      ruleAt(33, 19, w - 33, 19, accent, .55);
      ruleAt(33, h - 15, w - 33, h - 15, accent, .7);
    } else if (id == 'blueprint') {
      for (var n = 15.0; n < w; n += 9) {
        ruleAt(n, 7, n, 14, _color('#8CAFB1'));
      }
      for (var n = 20.0; n < h - 20; n += 12) {
        ruleAt(10, n, 16, n, _color('#9FB9B7'));
      }
      ruleAt(12, 16, w - 12, 16, accent, .8);
    } else if (id == 'carbon') {
      for (var n = 20.0; n < w - 17; n += 7) {
        ruleAt(n, 17, n + 3, 17, ink);
      }
      for (var n = 72.0; n < h - 28; n += 47) {
        g
          ..setFillColor(_color('#DFDFD8'))
          ..drawEllipse(12, h - n, 2.8, 2.8)
          ..fillPath();
      }
    } else if (id == 'ledger') {
      rect(0, 0, w, 9, _color('#21453F'));
      rect(0, h - 9, w, 9, _color('#21453F'));
    } else if (id == 'cobalt') {
      rect(40, h - 8, w - 80, 8, _color('#485A99'));
    } else if (id == 'seam') {
      for (var n = 24.0; n < h - 24; n += 9) {
        ruleAt(13, n, 17, n + 5, _color('#BE8896'), .85);
      }
    } else if (id == 'saffron') {
      rect(0, 0, 12, h, _color('#E2A02F'));
      ruleAt(18, 0, 18, h, ink, .65);
    }
  }
}
