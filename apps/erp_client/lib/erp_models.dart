class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
  static String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum ReportingPeriod {
  month('This month'),
  days30('Last 30 days'),
  year('This year');

  const ReportingPeriod(this.label);
  final String label;
  DateRange range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (this) {
      month => DateTime(now.year, now.month),
      days30 => DateTime(now.year, now.month, now.day - 29),
      year => DateTime(now.year),
    };
    return DateRange(start, DateTime(today.year, today.month, today.day + 1));
  }
}

enum ErpModule {
  accounts(
    'Accounts',
    'Sales Invoice',
    'customer_name',
    'posting_date',
    true,
    'status',
    'grand_total',
    'Bills & payments',
  ),
  selling(
    'Selling',
    'Sales Order',
    'customer_name',
    'transaction_date',
    true,
    'status',
    'grand_total',
    'Orders & customers',
  ),
  buying(
    'Buying',
    'Purchase Order',
    'supplier_name',
    'transaction_date',
    true,
    'status',
    'grand_total',
    'Suppliers & purchases',
  ),
  stock(
    'Stock',
    'Item',
    'item_name',
    null,
    false,
    'disabled',
    null,
    'Items & inventory',
  ),
  manufacturing(
    'Manufacturing',
    'Work Order',
    'production_item',
    'planned_start_date',
    true,
    'status',
    'qty',
    'Plan & make products',
  ),
  projects(
    'Projects',
    'Project',
    'project_name',
    'expected_start_date',
    true,
    'status',
    null,
    'Tasks & delivery',
  ),
  assets(
    'Assets',
    'Asset',
    'asset_name',
    'purchase_date',
    true,
    'status',
    null,
    'Equipment & property',
  ),
  quality(
    'Quality',
    'Quality Inspection',
    'item_name',
    'report_date',
    true,
    'status',
    null,
    'Checks & standards',
  );

  const ErpModule(
    this.label,
    this.doctype,
    this.titleField,
    this.dateField,
    this.companyScoped,
    this.statusField,
    this.amountField,
    this.description,
  );
  final String label, doctype, titleField, statusField, description;
  final String? dateField, amountField;
  final bool companyScoped;
  String get slug => doctype.toLowerCase().replaceAll(' ', '-');
  List<String> get fields => {
    'name',
    'modified',
    titleField,
    statusField,
    ?dateField,
    ?amountField,
    if ([accounts, selling, buying].contains(this)) 'currency',
  }.toList();
  List<List<dynamic>> filters(String company, DateRange range) => [
    if (companyScoped) ['company', '=', company],
    if (dateField != null) ...[
      [dateField!, '>=', DateRange.iso(range.start)],
      [dateField!, '<', DateRange.iso(range.end)],
    ],
  ];
  Uri uri(Uri base, {String? name, bool create = false}) => base.replace(
    pathSegments: [
      'app',
      slug,
      if (create)
        'new-$slug-${DateTime.now().microsecondsSinceEpoch}'
      else
        ?name,
    ],
    query: null,
    fragment: null,
  );
}

class ErpRecord {
  ErpRecord(Map<String, dynamic> data, this.module)
    : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  final ErpModule module;
  String get name => data['name']?.toString() ?? '';
  String get title =>
      data[module.titleField]?.toString().trim().isNotEmpty == true
      ? data[module.titleField].toString()
      : name;
  String get subtitle => name;
  String get status => module == ErpModule.stock
      ? (data['disabled'] == 1 ? 'Disabled' : 'Active')
      : (data[module.statusField]?.toString() ?? '');
  double? get amount =>
      module.amountField == null ? null : number(data[module.amountField!]);
  String? get currency => data['currency']?.toString();
  bool matches(String query) =>
      '$name $title $status'.toLowerCase().contains(query.trim().toLowerCase());
}

double number(Object? value) {
  if (value == null) return 0;
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (parsed == null || !parsed.isFinite) {
    throw const FormatException('Invalid numeric value');
  }
  return parsed;
}

class SalesDay {
  const SalesDay(this.day, this.amount);
  final DateTime day;
  final double amount;
}

class SalesScale {
  SalesScale(Iterable<double> amounts) {
    for (final amount in amounts) {
      if (amount < minimum) minimum = amount;
      if (amount > maximum) maximum = amount;
    }
  }
  double minimum = 0, maximum = 0;
  double fraction(double amount) =>
      (amount - minimum) / (maximum == minimum ? 1 : maximum - minimum);
}

class ErpSnapshot {
  const ErpSnapshot({
    required this.company,
    required this.currency,
    this.counts = const {},
    this.customers = 0,
    this.suppliers = 0,
    this.warehouses = 0,
    this.billed = 0,
    this.unpaidInvoices = 0,
    this.sales = const [],
    this.activity = const [],
  });
  final String company, currency;
  final Map<ErpModule, int?> counts;
  final int? customers, suppliers, warehouses;
  final double? billed;
  final int? unpaidInvoices;
  final List<SalesDay> sales;
  final List<ErpRecord> activity;
  bool get invoicesAvailable => billed != null;
  int? count(ErpModule module) =>
      counts.containsKey(module) ? counts[module] : 0;
}
