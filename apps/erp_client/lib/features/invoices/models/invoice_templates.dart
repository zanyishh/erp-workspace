class InvoiceTemplate {
  const InvoiceTemplate(this.id, this.name, this.category, this.accent);
  final String id, name, category;
  final int accent;
  int printAccent(String? override) {
    if (invoiceAccentColors.containsKey(override)) {
      return 0xff000000 | int.parse(override!.substring(1), radix: 16);
    }
    return id == 'ribbon' ? 0xff383f61 : accent;
  }

  String get thumbnailAsset => 'assets/invoice_templates/$id.png';
}

const invoiceAccentColors = {
  '#1646BD': 'Cobalt',
  '#195458': 'Teal',
  '#722C37': 'Burgundy',
  '#435A36': 'Olive',
  '#5438B1': 'Violet',
  '#9A462F': 'Terracotta',
  '#82500F': 'Ochre',
  '#36383C': 'Graphite',
};

const invoiceTemplates = [
  InvoiceTemplate('canopy', 'Violet Canopy', 'Studio', 0xFF5438B1),
  InvoiceTemplate('ribbon', 'Light Ribbon', 'Studio', 0xFF55346F),
  InvoiceTemplate('offset', 'Offset Grid', 'Editorial', 0xFF36383C),
  InvoiceTemplate('cobalt', 'Cobalt Fold', 'Studio', 0xFF1646BD),
  InvoiceTemplate('folio', 'Press Folio', 'Editorial', 0xFF722C37),
  InvoiceTemplate('ledger', 'Trade Ledger', 'Trade', 0xFF195458),
  InvoiceTemplate('terracotta', 'Clay Archive', 'Editorial', 0xFF9A462F),
  InvoiceTemplate('blueprint', 'Blueprint', 'Studio', 0xFF24576D),
  InvoiceTemplate('grove', 'Olive Grove', 'Editorial', 0xFF435A36),
  InvoiceTemplate('seam', 'Rose Stripe', 'Trade', 0xFF9B3D5D),
  InvoiceTemplate('mariner', 'Port Authority', 'Trade', 0xFF154862),
  InvoiceTemplate('carbon', 'Carbon Copy', 'Trade', 0xFF3F4551),
  InvoiceTemplate('saffron', 'Amber Mark', 'Trade', 0xFF82500F),
  InvoiceTemplate('pearl', 'Pearl Curve', 'Studio', 0xFF57528A),
  InvoiceTemplate('dispatch', 'Dispatch Column', 'Trade', 0xFF704A26),
];

InvoiceTemplate invoiceTemplateById(String id) => invoiceTemplates.firstWhere(
  (template) => template.id == id,
  orElse: () =>
      invoiceTemplates.firstWhere((template) => template.id == 'ledger'),
);
