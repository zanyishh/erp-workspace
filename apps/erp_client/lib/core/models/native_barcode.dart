import 'dart:convert';

import 'package:barcode/barcode.dart';
import 'package:xml/xml.dart';

String? barcodeCompanion(String options) {
  if (!options.trim().startsWith('{')) return null;
  try {
    final values = jsonDecode(options);
    return values is Map && values['valueField'] is String
        ? values['valueField'] as String
        : null;
  } on FormatException {
    return null;
  }
}

String barcodeText(String stored) {
  if (!stored.trimLeft().startsWith('<svg')) return stored;
  try {
    return XmlDocument.parse(stored).rootElement
            .getAttribute('data-barcode-value') ??
        '';
  } on XmlException {
    return '';
  }
}

Barcode barcodeFormat(String options, String text) {
  String format = 'CODE128';
  if (options.trim().startsWith('{')) {
    final config = jsonDecode(options);
    if (config is Map) {
      format = (config['format'] ?? format).toString().toUpperCase();
    }
  }
  return switch (format) {
    'CODE128' || 'AUTO' => Barcode.code128(),
    'CODE128A' => Barcode.code128(useCode128B: false, useCode128C: false),
    'CODE128B' => Barcode.code128(useCode128A: false, useCode128C: false),
    'CODE128C' => Barcode.code128(useCode128A: false, useCode128B: false),
    'CODE39' => Barcode.code39(),
    'CODE93' => Barcode.code93(),
    'EAN' => text.length == 8 ? Barcode.ean8() : Barcode.ean13(),
    'EAN13' => Barcode.ean13(),
    'EAN8' => Barcode.ean8(),
    'UPC' || 'UPCA' => Barcode.upcA(),
    'UPCE' => Barcode.upcE(),
    'ITF' => Barcode.itf(),
    'ITF14' => Barcode.itf14(),
    'CODABAR' => Barcode.codabar(),
    _ => throw FormatException('Unsupported barcode format $format.'),
  };
}

String encodeBarcode(String input, String options) {
  // Existing Desk SVGs are already serialized. A fresh edit always starts as text.
  if (input.trimLeft().startsWith('<svg')) return input;
  if (input.isEmpty) return '';
  final barcode = barcodeFormat(options, input);
  if (input.length > 256 || !barcode.isValid(input)) {
    throw const FormatException('Enter a valid barcode for this field.');
  }
  final svg = barcode.toSvg(input, width: 300, height: 70);
  return svg.replaceFirst(
    '<svg ',
    '<svg data-barcode-value="${const HtmlEscape().convert(input)}" ',
  );
}
