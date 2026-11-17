import '../../../core/models/native_models.dart';
import '../models/catalog_models.dart';

// Task phrases supplement the record names supplied by this account's server.
const _catalogTasks = {
  'Purchase Receipt':
      'receive goods from supplier vendor delivery goods receipt',
  'Delivery Note': 'ship goods dispatch customer order',
  'Sales Invoice': 'bill customer invoice a customer',
  'Purchase Invoice': 'record supplier bill vendor invoice',
  'Payment Entry': 'record customer payment pay supplier receive money',
  'Stock Entry': 'transfer stock between warehouses receive materials',
  'Stock Reconciliation': 'count stock adjust inventory physical count',
  'Material Request': 'request materials purchase requisition',
  'Work Order': 'manufacture goods start production finish production',
  'BOM': 'bill of materials product recipe',
  'Quotation': 'quote customer estimate',
  'Accounts Receivable': 'who owes us unpaid customer invoices',
  'Accounts Payable': 'who we owe unpaid supplier bills',
  'General Ledger': 'posted accounting transactions ledger entries',
  'Profit and Loss Statement': 'income statement earnings expenses',
};

class CatalogBrowseViewModel {
  CatalogBrowseViewModel(
    this._catalog, {
    this._create = false,
    this._allowReports = false,
    this._knittingOnly = false,
  });
  CatalogSnapshot _catalog;
  bool _create, _allowReports, _knittingOnly;
  bool _reportsSelected = false;
  String _query = '', _module = '';
  CatalogSnapshot get catalog => _catalog;
  bool get create => _create;
  bool get knittingOnly => _knittingOnly;
  bool get showReports => !_create && _allowReports;
  bool get reportsSelected => _reportsSelected;
  String get query => _query;
  String get module => modules.contains(_module) ? _module : '';
  Iterable<NativeType> get _allowed => _catalog.types.where(
    (type) => !_create || type.canCreate && !type.single,
  );
  List<String> get modules {
    final result = {
      for (final type in _allowed) type.module,
      if (showReports)
        for (final report in _catalog.reports)
          report['module']?.toString() ?? 'Other',
    }.toList()..sort();
    return List.unmodifiable(result);
  }

  bool Function(String, String) _matcher() {
    final selected = module;
    final words = _query.split(RegExp(r'\s+'));
    return (name, group) {
      if (selected.isNotEmpty && selected != group) {
        return false;
      }
      final terms = '$name $group ${_catalogTasks[name] ?? ''}'.toLowerCase();
      return words.every(terms.contains);
    };
  }

  List<NativeType> get types {
    final matches = _matcher();
    return List.unmodifiable(_allowed.where((t) => matches(t.name, t.module)));
  }

  List<Map<String, dynamic>> get reports {
    final matches = _matcher();
    return List.unmodifiable(
      _catalog.reports.where(
        (r) => matches(r['name'] as String, r['module']?.toString() ?? 'Other'),
      ),
    );
  }

  int get count => _reportsSelected ? reports.length : types.length;
  void search(String value) => _query = value.trim().toLowerCase();
  void selectModule(String value) => _module = value;
  void selectReports(bool value) => _reportsSelected = value;
  void updateCatalog(CatalogSnapshot value) => _catalog = value;
  void configure({
    required bool create,
    required bool allowReports,
    required bool knittingOnly,
  }) {
    _create = create;
    _allowReports = allowReports;
    _knittingOnly = knittingOnly;
  }
}
