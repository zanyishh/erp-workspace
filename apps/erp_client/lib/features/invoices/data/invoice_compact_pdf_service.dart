part of 'invoice_pdf_service.dart';

extension _CompactInvoice on _InvoiceSheet {
  pw.MultiPage _compactPage() {
    final receipt = format.isReceipt;
    final page = pw.PageTheme(
      pageFormat: format.pageFormat,
      margin: pw.EdgeInsets.all(receipt ? 9 : 24),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    return pw.MultiPage(
      pageTheme: page,
      maxPages: 10000,
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : txt('$title  /  ${v('name')}', size: 8, font: bold),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: txt('${context.pageNumber} / ${context.pagesCount}', size: 8),
      ),
      build: (_) => [
        if (hasLogo) _logoMark(),
        txt('$title  /  ${v('name')}', size: receipt ? 13 : 19, font: bold),
        pw.SizedBox(height: 6),
        if (receipt) ...[
          _pair(false),
          pw.SizedBox(height: 6),
          _pair(true),
        ] else
          _addresses(),
        pw.SizedBox(height: 7),
        _details(),
        pw.Divider(),
        if (receipt)
          for (final item in _rows(data['items'])) ..._receiptLine(item)
        else
          _table(),
        ..._summary(),
        ..._paymentDetails(),
        ..._notes(),
      ],
    );
  }

  List<pw.Widget> _receiptLine(Map<String, dynamic> item) {
    final (name, details) = _itemDescription(item);
    final hsn = _s(item['hsn_sac']);
    final qty = formatInvoiceNumber(item['qty'], indian: currency == 'INR');
    final quantityLabel = v('source_quantity_label');
    final rateLabel = v('source_rate_label');
    return [
      for (final line in _chunks(name, 32)) txt(line, font: bold, size: 10),
      for (final detail in details)
        for (final line in _chunks(detail, 36)) txt(line, size: 8),
      if (hsn.isNotEmpty) txt('HSN / SAC  $hsn', size: 8),
      txt(
        '${quantityLabel.isEmpty ? 'Qty' : quantityLabel}  $qty ${_s(item['uom'])}',
        size: 9,
      ),
      txt(
        '${rateLabel.isEmpty ? 'Rate' : rateLabel}  ${itemRate(item['rate'])}',
        size: 9,
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: txt(amount(item['amount']), font: bold),
      ),
      pw.Divider(thickness: .5),
    ];
  }
}
