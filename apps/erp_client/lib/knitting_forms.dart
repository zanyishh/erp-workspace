import 'dart:async';
import 'ui/workspace_art.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_api.dart';
import 'knitting_models.dart';
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';
import 'ui/access_gate.dart';
import 'document_editor.dart';

part 'knitting_entry_layout.dart';

class KnitField {
  const KnitField(
    this.key,
    this.label, {
    this.kind = 'text',
    this.options = const [],
    this.optional = false,
    this.value,
    this.finance = false,
  });
  final String key, label, kind;
  final List<String> options;
  final bool optional, finance;
  final dynamic value;
}

class KnitAction {
  const KnitAction(
    this.id,
    this.title,
    this.group,
    this.capability,
    this.fields, {
    this.needsJob = true,
  });
  final String id, title, group, capability;
  final List<KnitField> fields;
  final bool needsJob;

  IconData get icon => switch (id) {
    'create_job' => Icons.post_add_outlined,
    'revise_job' => Icons.edit_note_outlined,
    'close_job' => Icons.task_alt_outlined,
    'close_jobs' => Icons.playlist_add_check_circle_outlined,
    'reopen_job' => Icons.restore_outlined,
    'cancel_event' => Icons.undo_outlined,
    'receive_yarn' => Icons.move_to_inbox_outlined,
    'return_yarn' => Icons.assignment_return_outlined,
    'allocate_yarn' => Icons.account_tree_outlined,
    'transfer_yarn' => Icons.swap_horiz_rounded,
    'move_yarn' => Icons.warehouse_outlined,
    'repack_yarn' => Icons.inventory_2_outlined,
    'adjust_yarn' => Icons.exposure_outlined,
    'produce' => Icons.precision_manufacturing_outlined,
    'produce_bulk' => Icons.layers_outlined,
    'split_roll' => Icons.call_split_rounded,
    'quality' => Icons.fact_check_outlined,
    'plan' => Icons.edit_calendar_outlined,
    'holiday' => Icons.event_busy_outlined,
    'deliver' => Icons.local_shipping_outlined,
    'return_fabric' => Icons.assignment_returned_outlined,
    'transfer_fabric' => Icons.compare_arrows_rounded,
    'invoice' => Icons.receipt_long_outlined,
    'credit_invoice' => Icons.currency_exchange_outlined,
    'create_rate' => Icons.sell_outlined,
    'set_lot_charge' => Icons.price_change_outlined,
    'create_yarn_order' => Icons.add_shopping_cart_outlined,
    'bill_yarn' => Icons.shopping_cart_checkout_outlined,
    'create_estimate' => Icons.calculate_outlined,
    'accept_estimate' => Icons.approval_outlined,
    'job_from_estimate' => Icons.assignment_add,
    'create_machine' => Icons.add_business_outlined,
    'create_component' => Icons.extension_outlined,
    'replace_component' => Icons.change_circle_outlined,
    'component_breakage' => Icons.report_problem_outlined,
    'stoppage' => Icons.pause_circle_outline,
    'save_master' => Icons.library_books_outlined,
    'issue_consumable' => Icons.outbox_outlined,
    'return_consumable' => Icons.unarchive_outlined,
    'create_subcontract' => Icons.handshake_outlined,
    'subcontract_issue' => Icons.output_outlined,
    'subcontract_receive' => Icons.input_outlined,
    'subcontract_return' => Icons.keyboard_return_rounded,
    'subcontract_bill' => Icons.request_quote_outlined,
    'close_subcontract' => Icons.assignment_turned_in_outlined,
    'short_close_subcontract' => Icons.remove_done_outlined,
    'reopen_subcontract' => Icons.history_rounded,
    _ => Icons.description_outlined,
  };

  bool availableIn(WorkspaceContext workspace) =>
      workspace.allows(capability) &&
      !workspace.unavailableKnittingActions.contains(id);
  bool appearsIn(String destination) =>
      group == destination ||
      (id == 'cancel_event' && !needsJob && destination == 'Yarn');
}

const jobField = KnitField('job', 'Job', kind: 'Job');
const quantityField = KnitField('quantity_kg', 'Quantity · kg', kind: 'kg');
const unitsField = KnitField(
  'units',
  'Bags / cones moved or emptied',
  kind: 'integer',
  optional: true,
);
const lotField = KnitField('lot', 'Yarn lot', kind: 'Lot');
const reasonField = KnitField('reason', 'Reason');
const warehouseField = KnitField(
  'warehouse',
  'Godown',
  kind: 'Warehouse',
  optional: true,
);
const programmeField = KnitField(
  'programme',
  'Fabric programme',
  kind: 'programme',
);
const rateField = KnitField(
  'rate',
  'Rate per kg',
  kind: 'money',
  finance: true,
  value: '0',
);
const targetField = KnitField('target_kg', 'Target · kg', kind: 'kg');
const weightsField = KnitField(
  'weights_kg',
  'Individual roll weights · kg',
  kind: 'weights',
);
const lineField = KnitField('programme_line', 'Programme line', kind: 'line');
const machineField = KnitField('machine', 'Machine', kind: 'Machine');
const inputField = KnitField(
  'inputs',
  'Actual yarn consumption',
  kind: 'inputs',
);
const lossField = KnitField(
  'loss_kg',
  'Declared loss · kg',
  kind: 'kg',
  value: '0',
);
const datesFields = [
  KnitField('starts_at', 'Start · YYYY-MM-DD HH:MM', kind: 'datetime'),
  KnitField('ends_at', 'Finish · YYYY-MM-DD HH:MM', kind: 'datetime'),
];
const knitActions = <KnitAction>[
  KnitAction(
    'short_close_subcontract',
    'Release subcontract balance',
    'Billing',
    'lifecycle',
    [KnitField('subcontract', 'Subcontract', kind: 'Subcontract'), reasonField],
  ),
  KnitAction(
    'component_breakage',
    'Record component breakage',
    'Factory',
    'factory',
    [
      KnitField('component', 'Machine component', kind: 'Component'),
      KnitField('job', 'Job (optional)', kind: 'Job', optional: true),
      KnitField(
        'programme_line',
        'Programme line (when a job is selected)',
        kind: 'line',
        optional: true,
      ),
      KnitField(
        'operator',
        'Operator (blank uses your account)',
        kind: 'User',
        optional: true,
      ),
      KnitField(
        'employee',
        'Employee (optional)',
        kind: 'Employee',
        optional: true,
      ),
      KnitField('quantity', 'Broken units', kind: 'integer'),
      reasonField,
    ],
    needsJob: false,
  ),

  KnitAction(
    'cancel_event',
    'Correct yarn order, receipt or bill',
    'Billing',
    'lifecycle',
    [
      KnitField('event', 'Original company record', kind: 'CompanyEvent'),
      reasonField,
    ],
    needsJob: false,
  ),
  KnitAction(
    'reopen_subcontract',
    'Reopen subcontract',
    'Factory',
    'lifecycle',
    [
      KnitField(
        'subcontract',
        'Completed subcontract',
        kind: 'CompletedSubcontract',
      ),
      reasonField,
    ],
  ),

  KnitAction('close_jobs', 'Complete several jobs', 'Jobs', 'lifecycle', [
    KnitField('jobs', 'Reconciled jobs', kind: 'Jobs'),
  ], needsJob: false),

  KnitAction(
    'set_lot_charge',
    'Set extra material charge',
    'Billing',
    'billing',
    [
      lotField,
      KnitField('charge_item', 'Non-stock charge item', kind: 'ServiceItem'),
      KnitField('charge_rate', 'Charge per kg', kind: 'money'),
      reasonField,
    ],
    needsJob: false,
  ),

  KnitAction(
    'create_yarn_order',
    'Order yarn from supplier',
    'Billing',
    'billing',
    [
      KnitField('supplier', 'Supplier', kind: 'Supplier'),
      KnitField('item', 'Stock yarn item', kind: 'StockKgItem'),
      quantityField,
      rateField,
    ],
    needsJob: false,
  ),
  KnitAction('bill_yarn', 'Bill received yarn', 'Billing', 'billing', [
    KnitField('receipt', 'Original yarn receipt', kind: 'YarnReceipt'),
    quantityField,
    KnitField(
      'supplier',
      'Supplier (manual receipts only)',
      kind: 'Supplier',
      optional: true,
    ),
  ], needsJob: false),

  KnitAction('credit_invoice', 'Credit source invoice', 'Billing', 'billing', [
    KnitField('invoice_event', 'Source invoice', kind: 'InvoiceEvent'),
    quantityField,
    reasonField,
  ]),
  KnitAction('return_fabric', 'Receive fabric return', 'Delivery', 'delivery', [
    KnitField('delivery', 'Source delivery', kind: 'Delivery'),
    KnitField('rolls', 'Delivered rolls to return', kind: 'DeliveredRolls'),
    reasonField,
  ]),

  KnitAction('move_yarn', 'Transfer yarn to godown', 'Yarn', 'materials', [
    lotField,
    quantityField,
    unitsField,
    KnitField('target_warehouse', 'Destination godown', kind: 'Warehouse'),
    reasonField,
  ]),
  KnitAction('receive_yarn', 'Receive general yarn', 'Yarn', 'materials', [
    KnitField('item', 'Yarn item', kind: 'StockKgItem'),
    KnitField(
      'purchase_order',
      'Source yarn order (optional)',
      kind: 'PurchaseOrder',
      optional: true,
    ),
    KnitField(
      'material_owner',
      'Owner',
      kind: 'select',
      options: ['Customer', 'Owned'],
    ),
    KnitField('party', 'Material owner', kind: 'Customer', optional: true),
    quantityField,
    unitsField,
    warehouseField,
    KnitField('source_lot', 'Supplier / customer lot', optional: true),
    KnitField(
      'valuation_rate',
      'Owned cost per kg',
      kind: 'money',
      optional: true,
      finance: true,
    ),
  ], needsJob: false),
  KnitAction('return_yarn', 'Return general yarn', 'Yarn', 'materials', [
    lotField,
    quantityField,
    unitsField,
  ], needsJob: false),

  KnitAction(
    'transfer_fabric',
    'Reassign matching fabric',
    'Delivery',
    'lifecycle',
    [
      KnitField('rolls', 'Undelivered rolls', kind: 'UndeliveredRolls'),
      KnitField('target_job', 'Destination job', kind: 'Job'),
      KnitField(
        'target_programme_line',
        'Destination programme line',
        kind: 'line',
      ),
      reasonField,
    ],
  ),

  KnitAction(
    'produce_bulk',
    'Bulk / multi-size production',
    'Production',
    'production',
    [KnitField('entries', 'Production lines', kind: 'entries')],
  ),
  KnitAction('adjust_yarn', 'Review stock adjustment', 'Yarn', 'lifecycle', [
    lotField,
    KnitField('quantity_kg', 'Count difference · signed kg', kind: 'signed_kg'),
    KnitField(
      'units',
      'Physical unit difference',
      kind: 'signed_integer',
      optional: true,
    ),
    reasonField,
    KnitField(
      'valuation_rate',
      'Owned gain value per kg',
      kind: 'money',
      optional: true,
      finance: true,
    ),
    KnitField(
      'subcontract',
      'Subcontract custody (optional)',
      kind: 'Subcontract',
      optional: true,
    ),
  ]),
  KnitAction(
    'save_master',
    'Maintain industry master',
    'Factory',
    'configure',
    [
      KnitField(
        'master',
        'Existing definition (optional)',
        kind: 'Master',
        optional: true,
      ),
      KnitField(
        'category',
        'Category',
        kind: 'select',
        options: [
          'Fabric',
          'Yarn mill',
          'Yarn colour',
          'Yarn count',
          'Yarn variety',
          'Coordinator',
          'Elastane',
          'Construction',
          'Dia',
          'Machine type',
          'Gauge',
          'Ingredient',
          'Feeders',
          'Knit type',
          'Machine make',
          'QC defect',
          'Stoppage reason',
          'Stoppage group',
          'Shift',
          'Component setting',
          'Label setting',
          'Terms group',
        ],
      ),
      KnitField('title', 'Name'),
      KnitField(
        'enabled',
        'Available for new work',
        kind: 'toggle',
        value: true,
      ),
      KnitField('description', 'Description', optional: true),
      KnitField('value', 'Value', optional: true),
      KnitField('severity', 'Defect severity (optional)', optional: true),
      KnitField(
        'boundary_kg',
        'Component service boundary · kg',
        kind: 'kg',
        optional: true,
      ),
    ],
    needsJob: false,
  ),

  KnitAction('create_job', 'New job', 'Jobs', 'new_job', [
    KnitField('customer', 'Customer', kind: 'Customer'),
    KnitField('kind', 'Job kind', kind: 'select', options: ['Order', 'Sample']),
    KnitField(
      'material_mode',
      'Material ownership',
      kind: 'select',
      options: ['Customer', 'Owned'],
    ),
    targetField,
    programmeField,
    rateField,
    KnitField('due_date', 'Due · YYYY-MM-DD', kind: 'date', optional: true),
    KnitField('notes', 'Notes', optional: true),
  ], needsJob: false),
  KnitAction('revise_job', 'Revise programme', 'Jobs', 'lifecycle', [
    reasonField,
    programmeField,
    KnitField(
      'rate',
      'Rate per kg',
      kind: 'money',
      finance: true,
      optional: true,
    ),
  ]),
  KnitAction('close_job', 'Complete job', 'Jobs', 'lifecycle', []),
  KnitAction('reopen_job', 'Reopen job', 'Jobs', 'lifecycle', [reasonField]),
  KnitAction('receive_yarn', 'Receive yarn', 'Yarn', 'materials', [
    KnitField('item', 'Yarn item', kind: 'StockKgItem'),
    KnitField(
      'purchase_order',
      'Source yarn order (optional)',
      kind: 'PurchaseOrder',
      optional: true,
    ),
    KnitField(
      'material_owner',
      'Owner',
      kind: 'select',
      options: ['Customer', 'Owned'],
    ),
    KnitField('party', 'Material owner', kind: 'Customer', optional: true),
    quantityField,
    KnitField('units', 'Bags / units', kind: 'integer', value: '0'),
    warehouseField,
    KnitField(
      'charge_item',
      'Extra material charge item (optional)',
      kind: 'ServiceItem',
      optional: true,
      finance: true,
    ),
    KnitField(
      'charge_rate',
      'Extra material charge per kg',
      kind: 'money',
      optional: true,
      finance: true,
    ),
    KnitField(
      'valuation_rate',
      'Owned cost per kg',
      kind: 'money',
      optional: true,
      finance: true,
    ),
  ]),
  KnitAction('return_yarn', 'Return yarn', 'Yarn', 'materials', [
    lotField,
    quantityField,
    unitsField,
  ]),
  KnitAction('allocate_yarn', 'Allocate general yarn', 'Yarn', 'materials', [
    lotField,
    quantityField,
    unitsField,
  ]),
  KnitAction('transfer_yarn', 'Transfer to job', 'Yarn', 'materials', [
    lotField,
    quantityField,
    unitsField,
    KnitField('target_job', 'Destination job', kind: 'Job'),
  ]),
  KnitAction('repack_yarn', 'Repack / process yarn', 'Yarn', 'materials', [
    lotField,
    KnitField(
      'input_units',
      'Input bags / cones emptied',
      kind: 'integer',
      optional: true,
    ),
    KnitField('input_kg', 'Input · kg', kind: 'kg'),
    KnitField('output_kg', 'Output · kg', kind: 'kg'),
    lossField,
    KnitField('output_units', 'Output bags', kind: 'integer', value: '0'),
  ]),
  KnitAction('plan', 'Allocate machine', 'Planning', 'planning', [
    KnitField(
      'plan',
      'Existing allocation (optional)',
      kind: 'Plan',
      optional: true,
    ),
    lineField,
    machineField,
    KnitField(
      'shift',
      'Shift name (blank uses available shifts)',
      optional: true,
    ),
    ...datesFields,
    quantityField,
    KnitField(
      'required_yarn_kg',
      'Planned input demand · kg (optional)',
      kind: 'kg',
      optional: true,
    ),
  ]),
  KnitAction('holiday', 'Factory holiday', 'Planning', 'planning', [
    KnitField('date', 'Date · YYYY-MM-DD', kind: 'date'),
    KnitField(
      'machine',
      'Machine · leave empty for whole factory',
      kind: 'Machine',
      optional: true,
    ),
    KnitField('description', 'Description'),
  ], needsJob: false),
  KnitAction('produce', 'Record production', 'Production', 'production', [
    lineField,
    KnitField('machine', 'Machine', kind: 'Machine', optional: true),
    KnitField('shift', 'Shift'),
    weightsField,
    inputField,
    lossField,
    warehouseField,
  ]),
  KnitAction('quality', 'Inspect roll', 'Quality', 'quality', [
    KnitField('roll', 'Roll', kind: 'Roll'),
    KnitField(
      'decision',
      'Decision',
      kind: 'select',
      options: ['Released', 'On Hold', 'Rework', 'Rejected'],
    ),
    KnitField('defects', 'Quality defects', kind: 'Defects', optional: true),
    KnitField('remarks', 'Inspection notes'),
  ]),
  KnitAction('split_roll', 'Split roll', 'Production', 'production', [
    KnitField('roll', 'Original roll', kind: 'Roll'),
    weightsField,
    reasonField,
  ]),
  KnitAction('deliver', 'Create delivery', 'Delivery', 'delivery', [
    KnitField('rolls', 'Released rolls', kind: 'Rolls'),
    KnitField('destination', 'Delivery destination', optional: true),
    KnitField('transport', 'Transport / vehicle', optional: true),
    KnitField('transport_reference', 'Transport reference', optional: true),
  ]),
  KnitAction('invoice', 'Create invoice', 'Billing', 'billing', [
    KnitField('deliveries', 'Confirmed deliveries', kind: 'Deliveries'),
    KnitField(
      'quantity_kg',
      'Partial quantity · kg (empty = all unbilled)',
      kind: 'kg',
      optional: true,
    ),
  ]),
  KnitAction('cancel_event', 'Correct posted record', 'Jobs', 'lifecycle', [
    KnitField('event', 'Original job transaction', kind: 'Event'),
    reasonField,
  ]),
  KnitAction('create_machine', 'Add machine', 'Factory', 'factory', [
    KnitField('title', 'Machine name'),
    KnitField('dia', 'Dia'),
    KnitField('gauge', 'Gauge'),
    KnitField(
      'knit_type',
      'Knit type',
      kind: 'select',
      options: ['Tubular', 'Open width'],
    ),
    KnitField('capacity_kg', 'Capacity · kg per 8 hours', kind: 'kg'),
    KnitField(
      'shifts',
      'Available shifts · comma separated (blank uses all)',
      optional: true,
    ),
  ], needsJob: false),
  KnitAction('create_component', 'Install component', 'Factory', 'factory', [
    machineField,
    KnitField(
      'component_type',
      'Component',
      kind: 'select',
      options: ['Needle', 'Sinker', 'Cylinder', 'Dial'],
    ),
    KnitField('boundary_kg', 'Service boundary · kg', kind: 'kg'),
  ], needsJob: false),
  KnitAction('replace_component', 'Replace component', 'Factory', 'factory', [
    KnitField('component', 'Component', kind: 'Component'),
    reasonField,
    KnitField('boundary_kg', 'New boundary · kg', kind: 'kg', optional: true),
  ], needsJob: false),
  KnitAction('stoppage', 'Record stoppage', 'Factory', 'factory', [
    machineField,
    ...datesFields,
    reasonField,
  ], needsJob: false),
  KnitAction('create_subcontract', 'Subcontract order', 'Billing', 'billing', [
    KnitField('supplier', 'Supplier', kind: 'Supplier'),
    targetField,
    rateField,
    warehouseField,
  ]),
  KnitAction(
    'subcontract_issue',
    'Issue to subcontractor',
    'Yarn',
    'materials',
    [
      KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
      lotField,
      quantityField,
      unitsField,
    ],
  ),
  KnitAction(
    'subcontract_receive',
    'Receive subcontract fabric',
    'Factory',
    'factory',
    [
      KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
      lineField,
      weightsField,
      inputField,
      lossField,
      warehouseField,
    ],
  ),
  KnitAction(
    'subcontract_return',
    'Return from subcontractor',
    'Yarn',
    'materials',
    [
      KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
      lotField,
      quantityField,
      unitsField,
    ],
  ),
  KnitAction('subcontract_bill', 'Post supplier bill', 'Billing', 'billing', [
    KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
    quantityField,
  ]),
  KnitAction(
    'close_subcontract',
    'Complete subcontract',
    'Factory',
    'factory',
    [KnitField('subcontract', 'Subcontract', kind: 'Subcontract')],
  ),
  KnitAction('issue_consumable', 'Issue consumable', 'Factory', 'factory', [
    KnitField('item', 'Stock item', kind: 'Item'),
    KnitField('quantity', 'Quantity', kind: 'kg'),
    unitsField,
    warehouseField,
    KnitField('job', 'Job (optional)', kind: 'Job', optional: true),
    KnitField('lot', 'Owned yarn lot (optional)', kind: 'Lot', optional: true),
    KnitField('machine', 'Machine', kind: 'Machine', optional: true),
    reasonField,
  ], needsJob: false),
  KnitAction('return_consumable', 'Return consumable', 'Factory', 'factory', [
    KnitField('event', 'Original consumable issue', kind: 'ConsumableIssue'),
    KnitField('quantity', 'Quantity', kind: 'kg'),
    unitsField,
    reasonField,
  ], needsJob: false),
  KnitAction('create_estimate', 'New estimate', 'Billing', 'billing', [
    KnitField('customer', 'Customer', kind: 'Customer'),
    KnitField(
      'material_mode',
      'Owner',
      kind: 'select',
      options: ['Customer', 'Owned'],
    ),
    targetField,
    programmeField,
    rateField,
  ], needsJob: false),
  KnitAction('accept_estimate', 'Accept estimate', 'Billing', 'billing', [
    KnitField('quotation', 'Estimate', kind: 'Quotation'),
  ], needsJob: false),
  KnitAction('job_from_estimate', 'Job from estimate', 'Billing', 'new_job', [
    KnitField('quotation', 'Accepted estimate', kind: 'Quotation'),
  ], needsJob: false),
  KnitAction('create_rate', 'Agree party rate', 'Billing', 'billing', [
    KnitField('customer', 'Customer', kind: 'Customer'),
    KnitField('fabric', 'Fabric'),
    KnitField('yarn_count', 'Yarn count', optional: true),
    KnitField('gauge', 'Gauge', optional: true),
    rateField,
    KnitField(
      'effective_from',
      'Effective · YYYY-MM-DD',
      kind: 'date',
      optional: true,
    ),
  ], needsJob: false),
];

Future<Map<String, dynamic>?> pickKnitRecord(
  BuildContext context,
  ErpApi api,
  String company,
  String entity, {
  bool multiple = false,
  String? job,
}) async => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _RecordPicker(
    api: api,
    company: company,
    entity: entity,
    multiple: multiple,
    job: job,
  ),
);

class _RecordPicker extends StatefulWidget {
  const _RecordPicker({
    required this.api,
    required this.company,
    required this.entity,
    required this.multiple,
    this.job,
  });
  final ErpApi api;
  final String company, entity;
  final bool multiple;
  final String? job;
  @override
  State<_RecordPicker> createState() => _RecordPickerState();
}

class _RecordPickerState extends State<_RecordPicker> {
  String query = '';
  int start = 0;
  final selected = <String, Map<String, dynamic>>{};
  Timer? debounce;
  bool pendingSearch = false;
  late Future<Map<String, dynamic>> future = _load();
  Future<Map<String, dynamic>> _load() => widget.api.knittingLookup(
    widget.company,
    widget.entity,
    query,
    start: start,
    job: widget.job,
  );
  Future<void> _createCustomer() async {
    final revision = widget.api.accessRevision;
    final row = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (c) => DocumentEditor(
          api: widget.api,
          doctype: 'Customer',
          company: widget.company,
          onCreated: (doc) => Navigator.pop(c, <String, dynamic>{
            'name': doc.data['name'],
            'title': doc.data['customer_name'],
          }),
        ),
      ),
    );
    if (row != null &&
        mounted &&
        widget.api.accessReady &&
        widget.api.accessRevision == revision) {
      Navigator.pop(context, row);
    }
  }

  void search(String value, {bool now = false}) {
    debounce?.cancel();
    void apply() => setState(() {
      pendingSearch = false;
      query = value.trim();
      start = 0;
      future = _load();
    });
    if (now) {
      apply();
    } else {
      setState(() => pendingSearch = true);
      debounce = Timer(const Duration(milliseconds: 350), apply);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: AccessGate(
      api: widget.api,
      fullPage: false,
      revalidate: () async {
        selected.clear();
        final fresh = _load();
        setState(() {
          future = fresh;
        });
        await fresh;
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Display(
                      'SELECT ${_entityLabel(widget.entity).toUpperCase()}',
                      size: 28,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search by reference or name',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: search,
                onSubmitted: (v) => search(v, now: true),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: future,
                  builder: (c, s) {
                    if (pendingSearch ||
                        s.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Searching records',
                        ),
                      );
                    }
                    if (s.hasError) {
                      return MessagePanel(
                        title: 'COULD NOT LOAD',
                        message: s.error.toString(),
                        action: () => setState(() {
                          future = _load();
                        }),
                      );
                    }
                    if (!s.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = List<Map<String, dynamic>>.from(
                      (s.data!['rows'] as List).map(
                        (r) => Map<String, dynamic>.from(r),
                      ),
                    );
                    return Column(
                      children: [
                        Expanded(
                          child: rows.isEmpty
                              ? Center(
                                  child:
                                      widget.entity == 'Customer' &&
                                          s.data!['can_create'] == true
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'No matching customers.',
                                            ),
                                            TextButton.icon(
                                              onPressed: _createCustomer,
                                              icon: const Icon(
                                                Icons.person_add_alt_1_outlined,
                                              ),
                                              label: const Text(
                                                'Create customer',
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Text('No matching records.'),
                                )
                              : ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (_, i) {
                                    final row = rows[i];
                                    final name = row['name'] as String;
                                    final foreign =
                                        widget.job != null &&
                                        row['job'] != null &&
                                        row['job'] != widget.job;
                                    return ListTile(
                                      enabled: !foreign,
                                      title: Text(
                                        _recordTitle(row, widget.entity),
                                      ),
                                      subtitle: Text(
                                        [
                                          name,
                                          row['customer'],
                                          row['supplier'],
                                          row['item'],
                                          row['party'],
                                          row['category'],
                                          row['status'],
                                          row['state'],
                                          row['weight_kg'] != null
                                              ? '${row['weight_kg']} kg'
                                              : null,
                                          foreign
                                              ? 'Belongs to another job'
                                              : null,
                                        ].whereType<Object>().join(' · '),
                                      ),
                                      trailing: widget.multiple
                                          ? Checkbox(
                                              value: selected.containsKey(name),
                                              onChanged: foreign
                                                  ? null
                                                  : (v) => setState(() {
                                                      if (v == true) {
                                                        selected[name] = row;
                                                      } else {
                                                        selected.remove(name);
                                                      }
                                                    }),
                                            )
                                          : const Icon(Icons.chevron_right),
                                      onTap: () {
                                        if (widget.multiple) {
                                          setState(() {
                                            if (selected.containsKey(name)) {
                                              selected.remove(name);
                                            } else {
                                              selected[name] = row;
                                            }
                                          });
                                        } else {
                                          Navigator.pop(context, row);
                                        }
                                      },
                                    );
                                  },
                                ),
                        ),
                        if (start > 0 || s.data!['has_more'] == true)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: start == 0
                                    ? null
                                    : () => setState(() {
                                        start -= 50;
                                        future = _load();
                                      }),
                                child: const Text('Previous'),
                              ),
                              Text(
                                rows.isEmpty
                                    ? '0 records'
                                    : '${start + 1}–${start + rows.length}',
                              ),
                              TextButton(
                                onPressed: s.data!['has_more'] == true
                                    ? () => setState(() {
                                        start += 50;
                                        future = _load();
                                      })
                                    : null,
                                child: const Text('Next'),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (widget.multiple)
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, {
                          'names': selected.keys.toList(),
                          'records': selected.values.toList(),
                        }),
                  child: Text('Use ${selected.length} selected'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class KnittingCommandForm extends StatefulWidget {
  const KnittingCommandForm({
    super.key,
    required this.api,
    required this.workspace,
    required this.action,
    this.job,
    this.initial = const {},
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final KnitAction action;
  final Map<String, dynamic>? job;
  final Map<String, dynamic> initial;
  @override
  State<KnittingCommandForm> createState() => _KnittingCommandFormState();
}

class _KnittingCommandFormState extends State<KnittingCommandForm> {
  final formKey = GlobalKey<FormState>();
  final values = <String, dynamic>{};
  final references = <String, Map<String, dynamic>>{};
  final recordLabels = <(String, String), String>{};
  final scroll = ScrollController();
  KnittingDraft? draft;
  bool review = false, changed = false, checkingTotals = false, leaving = false;
  bool refreshingSources = false;
  Map<String, dynamic>? invoiceReview;
  String? validation;
  bool accessInvalidatedDraft = false;
  Map<String, dynamic>? freshJob;
  WorkspaceContext get workspace =>
      widget.api.contextFor(widget.workspace.company!) ?? widget.workspace;
  Map<String, dynamic>? get job => freshJob ?? widget.job ?? references['job'];
  Map<String, dynamic>? get sourceEvent => switch (widget.action.id) {
    'bill_yarn' => references['receipt'],
    'return_consumable' => references['event'],
    _ => null,
  };
  String? get sourceVersion =>
      job?['modified'] as String? ?? sourceEvent?['job_modified'] as String?;
  void _maskFinancialFields() {
    if (workspace.allows('financial_read')) return;
    void remove(dynamic value) {
      if (value is Map) {
        value.removeWhere(
          (k, _) => const {
            'rate',
            'charge_item',
            'charge_rate',
            'valuation_rate',
            'income_account',
            'expense_account',
          }.contains(k),
        );
        value.values.forEach(remove);
      } else if (value is List) {
        value.forEach(remove);
      }
    }

    remove(values);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _markDirty() => changed = true;

  void _scrollToStart() {
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  List<KnitField> get fields => [
    if (widget.action.needsJob && widget.job == null) jobField,
    ...widget.action.fields.where(
      (f) => !f.finance || workspace.allows('financial_read'),
    ),
  ];
  @override
  void initState() {
    super.initState();
    for (final f in fields) {
      if (f.value != null) {
        values[f.key] = f.value;
      } else if (f.kind == 'select' && f.key != 'decision') {
        values[f.key] = f.options.first;
      }
    }
    values.addAll(
      jsonDecode(jsonEncode(widget.initial)) as Map<String, dynamic>,
    );
    if (widget.job != null) {
      values['job'] = widget.job!['name'];
      if (widget.action.id == 'revise_job') {
        _loadProgramme(widget.job!);
      }
    }
    _maskFinancialFields();
  }

  void _loadProgramme(Map<String, dynamic> source) {
    values['programme'] = jsonDecode(jsonEncode(source['programme'] ?? []));
  }

  void _changeSourceJob(Map<String, dynamic>? next) {
    final previous = values['job'];
    if (previous == next?['name']) return;
    freshJob = null;
    if (previous != null) {
      // A roll, allocation or yarn input selected for one job cannot be
      // reviewed under the next. Keep the operator's independent text fields.
      for (final f in fields.where(
        (f) =>
            f.key != 'job' &&
            (_nestedKinds.contains(f.kind) || f.kind == 'line' || _isPicker(f)),
      )) {
        values.remove(f.key);
        references.remove(f.key);
      }
      if (widget.action.id == 'revise_job') values.remove('rate');
    }
    if (widget.action.id == 'revise_job' && next != null) _loadProgramme(next);
  }

  bool get busy =>
      refreshingSources ||
      draft?.state == CommandState.posting ||
      draft?.state == CommandState.checking;
  void _finish() => Navigator.pop(context, draft?.result);

  Future<void> _leave() async {
    if (busy || checkingTotals || leaving) return;
    if (draft?.state == CommandState.confirmed) {
      _finish();
      return;
    }
    if (!changed && draft?.state != CommandState.uncertain) {
      Navigator.pop(context);
      return;
    }
    leaving = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave this entry?'),
        content: Text(
          draft?.state == CommandState.uncertain
              ? 'The save result is uncertain. Keep the request reference to check its status before posting again.'
              : 'Your unsaved entry will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    leaving = false;
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _review() async {
    if (!widget.action.availableIn(workspace) ||
        !widget.api.accessReady ||
        draft?.state == CommandState.uncertain) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final invalid = formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        duration: workspaceMotion(context),
        alignment: .2,
      );
      return;
    }
    try {
      final discrepancy = _quantityDiscrepancy();
      if (discrepancy != null) {
        setState(() => validation = discrepancy);
        return;
      }
      if (values['target_job'] != null) {
        values['target_modified'] = references['target_job']?['modified'];
      }
      if (values['plan'] != null) {
        values['plan_modified'] = references['plan']?['modified'];
      }
      if (values['master'] != null) {
        values['master_modified'] = references['master']?['modified'];
      }
      if (values['quotation'] != null) {
        values['quotation_modified'] = references['quotation']?['modified'];
      }
      values.removeWhere((k, v) => v == null || v == '');
      values.remove('preview_hash');
      final frozen = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(values)) as Map,
      );
      draft = KnittingDraft(widget.action.id, frozen);
      final reviewed = draft;
      final accessRevision = widget.api.accessRevision;
      accessInvalidatedDraft = false;
      _scrollToStart();
      setState(() {
        review = true;
        validation = null;
        checkingTotals = widget.action.id == 'invoice';
        invoiceReview = null;
      });
      if (widget.action.id == 'invoice') {
        final result = await widget.api.knittingInvoicePreview(
          widget.workspace.company!,
          frozen,
          sourceVersion,
        );
        if (!mounted ||
            !identical(reviewed, draft) ||
            accessRevision != widget.api.accessRevision ||
            !widget.api.accessReady) {
          return;
        }
        setState(() {
          invoiceReview = result;
          checkingTotals = false;
          draft = KnittingDraft(widget.action.id, {
            ...frozen,
            'preview_hash': result['preview_hash'],
          }, requestId: draft!.requestId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          review = e is ErpException && e.staleDocument && draft != null;
          if (review) {
            draft!.state = CommandState.stale;
            draft!.error = e.toString();
          } else {
            validation = e.toString();
          }
          checkingTotals = false;
        });
      }
    }
  }

  String? _quantityDiscrepancy() {
    Kg total(Iterable<dynamic> items) => items.fold(
      Kg.parse('0'),
      (sum, value) => sum + Kg.parse(value.toString()),
    );
    final id = widget.action.id;
    if (id == 'create_job' || id == 'create_estimate') {
      final target = Kg.parse(values['target_kg'].toString());
      final programme = total(
        (values['programme'] as List).map((row) => row['target_kg']),
      );
      if (target.compareTo(programme) != 0) {
        return 'The fabric programme totals $programme kg. Match it to the $target kg target before review.';
      }
    }
    if (const {'produce', 'produce_bulk', 'subcontract_receive'}.contains(id)) {
      final entries = id == 'produce_bulk'
          ? values['entries'] as List
          : [values];
      for (final (i, row) in entries.indexed) {
        final yarn = total(
          (row['inputs'] as List).map((input) => input['quantity_kg']),
        );
        final fabric = total(row['weights_kg'] as List);
        final loss = Kg.parse((row['loss_kg'] ?? '0').toString());
        if (yarn.compareTo(fabric + loss) != 0) {
          final line = id == 'produce_bulk'
              ? 'Line ${i + 1} uses'
              : 'This entry uses';
          return '$line $yarn kg of yarn. Match it to $fabric kg of fabric plus $loss kg of loss before review.';
        }
      }
    }
    return null;
  }

  Future<void> _post() async {
    if (!widget.api.accessReady ||
        accessInvalidatedDraft ||
        !widget.action.availableIn(workspace)) {
      return;
    }
    final d = draft!;
    final future = d.submit(
      () => widget.api.knittingCommand(
        widget.workspace.company!,
        d.action,
        d.values,
        d.requestId,
        modified: sourceVersion,
      ),
    );
    setState(() {});
    await future;
    if (!mounted || !identical(d, draft)) return;
    setState(() {
      if (d.state == CommandState.rejected) {
        validation = d.error;
        review = false;
        draft = null;
        invoiceReview = null;
      }
    });
  }

  Future<void> _check() async {
    final future = draft!.check(
      () => widget.api.knittingCommandStatus(
        widget.workspace.company!,
        draft!.requestId,
      ),
    );
    setState(() {});
    await future;
    if (mounted) setState(() {});
  }

  Future<void> _reloadStaleSources() async {
    if (busy || !widget.api.accessReady) return;
    setState(() => refreshingSources = true);
    try {
      final company = workspace.company!;
      final name = values['job'] as String?;
      final revision = widget.api.accessRevision;
      Map<String, dynamic>? latest;
      if (name != null) {
        final snapshot = await widget.api.knittingSnapshot(company, job: name);
        latest = snapshot
            .rows('jobs')
            .where((j) => j['name'] == name)
            .firstOrNull;
        if (latest == null) {
          throw const ErpException('The source job is no longer available.');
        }
      }
      if (!mounted ||
          revision != widget.api.accessRevision ||
          !widget.api.accessReady) {
        return;
      }
      setState(() {
        freshJob = latest;
        for (final f in fields.where(
          (f) =>
              f.key != 'job' &&
              (_isPicker(f) ||
                  f.kind == 'line' ||
                  const {'entries', 'inputs'}.contains(f.kind)),
        )) {
          values.remove(f.key);
          references.remove(f.key);
        }
        if (widget.action.id == 'revise_job' && latest != null) {
          _loadProgramme(latest);
          values.remove('rate');
        }
        invoiceReview = null;
        draft = null;
        review = false;
        validation =
            'Current sources loaded. Check your programme and selections before reviewing again.';
      });
      _scrollToStart();
    } catch (e) {
      if (mounted) setState(() => draft?.error = e.toString());
    } finally {
      if (mounted) setState(() => refreshingSources = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: AccessGate(
      api: widget.api,
      revalidate: () async {
        final effective = widget.api.contextFor(widget.workspace.company!);
        invoiceReview = null;
        checkingTotals = false;
        accessInvalidatedDraft = true;
        if (effective == null || !widget.action.availableIn(effective)) {
          throw const ErpException(
            'Your access to this action changed. Your entry has not been posted.',
          );
        }
        _maskFinancialFields();
        recordLabels.clear();
        references.clear();
        if (values['job'] != null) {
          final source = await widget.api.knittingSnapshot(
            effective.company!,
            job: values['job'] as String,
          );
          freshJob = source
              .rows('jobs')
              .where((r) => r['name'] == values['job'])
              .firstOrNull;
          if (freshJob == null) {
            throw const ErpException('This source job is no longer available.');
          }
        }
        setState(() {
          review =
              draft?.state == CommandState.uncertain ||
              draft?.state == CommandState.posting;
          validation =
              'Access refreshed. Review the current sources and your retained entry again.';
          if (!review) draft = null;
        });
      },
      child: _EntryPage(
        company: workspace.company!,
        action: widget.action,
        job:
            job ??
            (sourceEvent?['job'] == null
                ? null
                : {'name': sourceEvent!['job']}),
        scroll: scroll,
        review: review,
        confirmed: draft?.state == CommandState.confirmed,
        error: !review ? validation : null,
        footer: _footer(),
        child: review
            ? _reviewPanel()
            : Form(
                key: formKey,
                onChanged: _markDirty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in _entrySections(
                      widget.action,
                      fields,
                    ).entries)
                      _EntrySection(
                        title: section.key,
                        child: _grid(section.value, values),
                      ),
                    if (fields.isEmpty)
                      const _EntrySection(
                        title: 'Job completion',
                        child: Text(
                          'Review this job before marking it complete.',
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ),
  );
  Widget? _footer() {
    if (!review) {
      return FilledButton.icon(
        onPressed: _review,
        icon: const Icon(Icons.arrow_forward, size: 17),
        label: const Text('Review entry'),
      );
    }
    if (checkingTotals || accessInvalidatedDraft) return null;
    final state = draft!.state;
    if (state == CommandState.confirmed) {
      return FilledButton(onPressed: _finish, child: const Text('Done'));
    }
    if (state == CommandState.stale) {
      return FilledButton.icon(
        onPressed: refreshingSources ? null : _reloadStaleSources,
        icon: const Icon(Icons.refresh),
        label: Text(
          refreshingSources ? 'Reloading…' : 'Reload current sources',
        ),
      );
    }
    if (state == CommandState.uncertain) {
      return FilledButton.icon(
        onPressed: _check,
        icon: const Icon(Icons.sync),
        label: const Text('Check save status'),
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      children: [
        if (!busy)
          TextButton(
            onPressed: () {
              _scrollToStart();
              setState(() {
                review = false;
                draft = null;
              });
            },
            child: const Text('Edit entry'),
          ),
        FilledButton(
          onPressed: busy ? null : _post,
          child: Text(busy ? 'Waiting for ERP…' : 'Confirm & post'),
        ),
      ],
    );
  }

  Widget _grid(List<KnitField> descriptors, Map<String, dynamic> target) =>
      _FieldGrid(
        fields: descriptors,
        buildField: (field) => _field(field, target),
      );
  Widget _reviewPanel() {
    if (accessInvalidatedDraft) {
      return Panel(
        border: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Display('CHECK THE PREVIOUS SAVE', size: 28),
            const SizedBox(height: 12),
            const Text(
              'Access changed while this request was open. Check its result before reviewing another entry.',
            ),
            SelectableText('Request ${draft!.requestId}'),
            FilledButton(
              onPressed: () async {
                await _check();
                if (!mounted) return;
                setState(() {
                  if (draft?.state == CommandState.editing) {
                    review = false;
                    draft = null;
                    accessInvalidatedDraft = false;
                  } else if (draft?.state == CommandState.confirmed) {
                    _finish();
                  }
                });
              },
              child: const Text('Check save status'),
            ),
          ],
        ),
      );
    }
    if (checkingTotals) {
      return const Panel(
        border: true,
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Display('CHECKING ERP TOTALS', size: 28),
              SizedBox(height: 10),
              Text('Your invoice is being calculated. Nothing has been saved.'),
            ],
          ),
        ),
      );
    }
    final d = draft!;
    final confirmed = d.state == CommandState.confirmed;
    return Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: workspaceMotion(context),
                child: Icon(
                  key: ValueKey(confirmed),
                  confirmed
                      ? Icons.check_circle_outline
                      : Icons.fact_check_outlined,
                  color: confirmed
                      ? const Color(0xFF3E6B54)
                      : WorkspaceTheme.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Display(
                  confirmed ? 'SAVED IN ERP' : 'REVIEW BEFORE POSTING',
                  size: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            confirmed
                ? 'Posted to ${workspace.company}.'
                : 'Confirming will post this entry to ${workspace.company}.',
          ),
          const SizedBox(height: 20),
          if (invoiceReview != null && !confirmed) ...[
            const SizedBox(height: 20),
            Panel(
              border: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Display('INVOICE · ${invoiceReview!['currency']}', size: 26),
                  const SizedBox(height: 12),
                  for (final row in invoiceReview!['items'] as List)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${row['item']}\n${row['quantity']} ${row['uom']} × ${row['rate']}',
                            ),
                          ),
                          Text(row['amount'].toString()),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  for (final (key, label) in [
                    ('net_total', 'Net total'),
                    ('tax_total', 'Tax total'),
                    ('grand_total', 'Total to post'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            invoiceReview![key].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (!confirmed) ...[
            for (final f in fields.where((f) => _hasValue(d.values[f.key])))
              _reviewField(f, d.values[f.key]),
          ],
          if (confirmed || d.state == CommandState.uncertain) ...[
            const Divider(height: 28),
            SelectableText(
              'Request ${d.requestId}',
              style: const TextStyle(fontSize: 11, color: WorkspaceTheme.muted),
            ),
          ],
          if (d.error != null && !confirmed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                d.state == CommandState.stale
                    ? '${d.error}\nReload the current sources and review your entry again.'
                    : '${d.error}\nCheck status before changing or posting this entry again.',
                style: const TextStyle(color: Color(0xFFA23F38)),
              ),
            ),
          if (confirmed) ...[const SizedBox(height: 12), _savedOutcome(d)],
        ],
      ),
    );
  }

  Widget _savedOutcome(KnittingDraft draft) {
    final data = Map<String, dynamic>.from(draft.result?['data'] as Map? ?? {});
    final rolls = data['rolls'] as List?;
    final sources = <(String, String)>[
      if (data['invoice'] is String)
        (
          data['voucher_type'] == 'Purchase Invoice'
              ? 'Purchase Invoice'
              : 'Sales Invoice',
          data['invoice'] as String,
        ),
      if (data['purchase_order'] is String)
        ('Purchase Order', data['purchase_order'] as String),
      if (data['quotation'] is String)
        ('Quotation', data['quotation'] as String),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (data['quantity_kg'] != null)
              _outcomeMetric('Quantity', '${data['quantity_kg']} kg'),
            if (rolls != null) _outcomeMetric('Rolls', '${rolls.length} rolls'),
            if (data['consumed_kg'] != null)
              _outcomeMetric('Yarn consumed', '${data['consumed_kg']} kg'),
            if (data['loss_kg'] != null)
              _outcomeMetric('Declared loss', '${data['loss_kg']} kg'),
            if (data['amount'] != null && workspace.allows('financial_read'))
              _outcomeMetric('Document total', data['amount'].toString()),
            if (data['status'] != null)
              _outcomeMetric('Status', data['status'].toString()),
            if (data['completed'] is List)
              _outcomeMetric(
                'Completed jobs',
                '${(data['completed'] as List).length} jobs',
              ),
          ],
        ),
        for (final (key, label) in [
          ('job', 'Job'),
          ('lot', 'Yarn lot'),
          ('plan', 'Machine allocation'),
          ('machine', 'Machine'),
          ('inspection', 'Inspection'),
          ('subcontract', 'Subcontract'),
          ('component', 'Component'),
        ])
          if (data[key] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText('$label · ${data[key]}'),
            ),
        if (data['destination'] != null && data['destination'] != '')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Destination · ${data['destination']}'),
          ),
        for (final (type, name) in sources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            subtitle: Text(type),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DocumentEditor(
                  api: widget.api,
                  doctype: type,
                  name: name,
                  company: workspace.company,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _outcomeMetric(String label, String value) => Container(
    constraints: const BoxConstraints(minWidth: 170),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: WorkspaceTheme.canvas,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  bool _hasValue(dynamic v) =>
      v != null && v != '' && (v is! List || v.isNotEmpty);
  String _lineName(dynamic id, {bool destination = false}) {
    final source = destination ? references['target_job'] : job;
    final lines = source?['programme'] as List? ?? [];
    for (final (i, row) in lines.indexed) {
      if (row['id'] == id) return _programmeName(row, i);
    }
    return 'Programme line · $id';
  }

  String _valueLabel(KnitField f, dynamic value) {
    if (f.kind == 'line') {
      return _lineName(value, destination: f.key == 'target_programme_line');
    }
    if (f.kind == 'weights') {
      return (value as List).map((v) => '$v kg').join(', ');
    }
    if (f.kind == 'measurements') return (value as List).join(', ');
    if ((f.kind == 'kg' || f.kind == 'signed_kg') && f.label.contains('kg')) {
      return '$value kg';
    }
    if (f.kind == 'toggle' || value is bool) {
      return value == true || value == 1 ? 'Yes' : 'No';
    }
    if (_isPicker(f)) {
      String recordName(dynamic v) {
        final id = v is Map ? v['job'] : v;
        if (id == null) return f.label;
        final known = recordLabels[(f.kind, id.toString())];
        return known ?? '${_entityLabel(_entityFor(f.kind))} · $id';
      }

      return value is List
          ? value.map(recordName).join('\n')
          : recordName(value);
    }
    return value is List
        ? value.whereType<Object>().join(', ')
        : value.toString();
  }

  Widget _reviewField(KnitField f, dynamic value) {
    if (_nestedKinds.contains(f.kind)) {
      final descriptors = _childFields(
        f.kind,
        workspace.allows('financial_read'),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 28),
          Text(f.label, style: displayStyle(25)),
          for (final (i, row) in (value as List).indexed)
            if (row is Map)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _LineSheet(
                  title: _rowTitle(f, row, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final rf in [
                        ...descriptors,
                        if (f.kind == 'programme') ..._retainedProgrammeFields,
                      ])
                        if (_hasValue(row[rf.key]) &&
                            (f.kind != 'programme' || rf.key != 'fabric'))
                          _reviewField(rf, row[rf.key]),
                    ],
                  ),
                ),
              ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              f.label.split(' (').first.split(' · ').first,
              style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              _valueLabel(f, value),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _rowTitle(KnitField f, Map row, int i) => switch (f.kind) {
    'programme' =>
      (row['fabric'] as String?)?.trim().isNotEmpty == true
          ? row['fabric'] as String
          : 'Fabric ${i + 1}',
    'entries' => 'Production line ${i + 1}',
    _ => 'Yarn input ${i + 1}',
  };
  Widget _field(KnitField f, Map<String, dynamic> target) {
    if (f.kind == 'toggle') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: target[f.key] == true || target[f.key] == 1,
        onChanged: (v) => setState(() {
          target[f.key] = v;
          changed = true;
        }),
      );
    }
    if (_nestedKinds.contains(f.kind)) {
      return _rowsField(f, target);
    }
    if (f.kind == 'weights' || f.kind == 'measurements') {
      return TextFormField(
        initialValue: (target[f.key] as List? ?? []).join(', '),
        decoration: InputDecoration(
          labelText: f.label,
          helperMaxLines: 2,
          helperText: switch (f.key) {
            'gsm' => 'Grams per square metre, e.g. 180, 200',
            'll' => 'Separate loop lengths with a comma, e.g. 2.7, 2.9',
            _ => 'Separate roll weights with a comma, e.g. 24, 25.500',
          },
        ),
        onChanged: (v) => target[f.key] = v
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        validator: (v) {
          try {
            if (f.optional && (v ?? '').trim().isEmpty) return null;
            final parts = (v ?? '').split(',');
            if (f.kind == 'measurements') {
              final limit = f.key == 'gsm' ? 2 : 3;
              if (parts.length > limit) return 'Enter at most $limit values.';
            }
            for (final x in parts) {
              final quantity = Kg.parse(x.trim());
              if (f.kind == 'measurements' && quantity.milli == BigInt.zero) {
                return 'Enter a positive measurement.';
              }
            }
            return null;
          } catch (_) {
            return f.kind == 'measurements'
                ? 'Use positive values with up to 3 decimal places.'
                : 'Enter valid individual kg, up to 3 decimal places.';
          }
        },
      );
    }
    if (f.kind == 'select' && f.options.length == 2) {
      final selected = target[f.key]?.toString() ?? f.options.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            f.label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final option in f.options)
                ButtonSegment(value: option, label: Text(option)),
            ],
            selected: {selected},
            onSelectionChanged: (choice) => setState(() {
              target[f.key] = choice.single;
              changed = true;
            }),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? WorkspaceTheme.palePeach
                    : _paper,
              ),
              foregroundColor: const WidgetStatePropertyAll(WorkspaceTheme.ink),
            ),
          ),
        ],
      );
    }
    if (f.kind == 'select') {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: target[f.key]?.toString(),
        hint: f.key == 'decision' ? const Text('Choose a decision') : null,
        validator: (value) => f.key == 'decision' && value == null
            ? 'Choose an inspection decision.'
            : null,
        decoration: InputDecoration(labelText: f.label),
        items: f.options
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) {
          target[f.key] = v;
          changed = true;
        },
      );
    }
    if (f.kind == 'line') {
      final source = f.key == 'target_programme_line'
          ? references['target_job']
          : job;
      final lines = source?['programme'] as List? ?? [];
      final selected = lines.any((r) => r['id'] == target[f.key])
          ? target[f.key] as String?
          : null;
      return DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey((f.key, source?['name'], references['plan']?['name'])),
        initialValue: selected,
        decoration: InputDecoration(
          labelText: f.label,
          helperText: lines.isEmpty
              ? (source == null
                    ? 'Choose the job to see its fabric programme.'
                    : 'This job has no programme lines.')
              : null,
          helperMaxLines: 2,
        ),
        items: [
          for (final (i, r) in lines.indexed)
            DropdownMenuItem<String>(
              value: r['id'] as String,
              child: Text(
                _programmeName(r, i),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => target[f.key] = v,
        validator: (v) => v == null && (!f.optional || source != null)
            ? 'Choose a programme line.'
            : null,
      );
    }
    if (_isPicker(f)) {
      final entity = _entityFor(f.kind);
      final multi = entity != f.kind;
      return FormField<dynamic>(
        initialValue: target[f.key],
        validator: (_) =>
            !f.optional &&
                (target[f.key] == null ||
                    (target[f.key] is List && (target[f.key] as List).isEmpty))
            ? 'Choose ${f.label.toLowerCase()}.'
            : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final row = await pickKnitRecord(
                  context,
                  widget.api,
                  widget.workspace.company!,
                  entity,
                  multiple: multi,
                  job: values['job'] as String?,
                );
                if (row != null && mounted) {
                  setState(() {
                    if (f.key == 'job') _changeSourceJob(row);
                    target[f.key] = f.kind == 'Jobs'
                        ? (row['records'] as List)
                              .map(
                                (r) => <String, dynamic>{
                                  'job': r['name'],
                                  'modified': r['modified'],
                                },
                              )
                              .toList()
                        : multi
                        ? row['names']
                        : row['name'];
                    for (final record
                        in multi ? row['records'] as List : [row]) {
                      final name = record['name'].toString();
                      final title = _recordTitle(record, entity);
                      recordLabels[(f.kind, name)] = title == name
                          ? name
                          : '$title · $name';
                    }
                    if (identical(target, values)) references[f.key] = row;
                    if (f.key == 'plan') {
                      for (final k in [
                        'programme_line',
                        'machine',
                        'starts_at',
                        'ends_at',
                        'quantity_kg',
                        'required_yarn_kg',
                      ]) {
                        values[k] = row[k];
                      }
                    }
                    if (f.key == 'master') {
                      final raw = row['specification'];
                      final spec = raw is String ? jsonDecode(raw) : raw;
                      values.addAll({
                        'title': row['title'],
                        'category': row['category'],
                        'enabled': row['enabled'] != 0,
                        if (spec is Map) ...Map<String, dynamic>.from(spec),
                      });
                    }

                    changed = true;
                  });
                  state.didChange(target[f.key]);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: f.label,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  errorText: state.errorText,
                  suffixIcon: const Icon(Icons.search, size: 18),
                ),
                child: Text(
                  _hasValue(target[f.key])
                      ? _valueLabel(f, target[f.key])
                      : 'Choose a record',
                  style: TextStyle(
                    color: _hasValue(target[f.key])
                        ? WorkspaceTheme.ink
                        : WorkspaceTheme.muted,
                  ),
                ),
              ),
            ),
            if (f.optional && target[f.key] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      if (f.key == 'job') _changeSourceJob(null);
                      target.remove(f.key);
                      if (identical(target, values)) references.remove(f.key);
                      changed = true;
                    });
                    state.didChange(null);
                  },
                  child: const Text('Clear selection'),
                ),
              ),
          ],
        ),
      );
    }
    return TextFormField(
      key: ValueKey((
        f.key,
        references['master']?['name'],
        references['plan']?['name'],
        _isRevisionRate(f) ? values['job'] : null,
      )),
      initialValue: target[f.key]?.toString(),
      decoration: InputDecoration(
        labelText: f.label,
        helperText: _isRevisionRate(f)
            ? 'Leave blank to keep line rates. Enter a rate to apply it to every programme line.'
            : null,
        helperMaxLines: 3,
      ),
      maxLines: const {'notes', 'remarks', 'reason'}.contains(f.key) ? 2 : 1,
      keyboardType: ['kg', 'money', 'integer'].contains(f.kind)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (v) => target[f.key] = v,
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return f.optional ? null : 'Enter ${f.label.toLowerCase()}.';
        }
        try {
          if (f.kind == 'signed_kg') {
            Kg.parse(v.startsWith('-') ? v.substring(1) : v);
          }
          if (f.kind == 'kg') {
            Kg.parse(v);
          }
          if (f.kind == 'money' && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)) {
            return 'Use up to two decimal places.';
          }
          if (f.kind == 'signed_integer' && !RegExp(r'^-?\d+$').hasMatch(v)) {
            return 'Enter a whole number difference.';
          }
          if (f.kind == 'integer' && !RegExp(r'^\d+$').hasMatch(v)) {
            return 'Enter a whole number.';
          }
          if (['date', 'datetime'].contains(f.kind) &&
              DateTime.tryParse(v) == null) {
            return 'Enter a valid date.';
          }
        } catch (_) {
          return 'Enter valid kg, up to 3 decimal places.';
        }
        return null;
      },
    );
  }

  bool _isRevisionRate(KnitField field) =>
      field.key == 'rate' && widget.action.id == 'revise_job';

  Widget _rowsField(KnitField f, Map<String, dynamic> target) {
    final rows = (target[f.key] ??= <Map<String, dynamic>>[]) as List;
    final programme = f.kind == 'programme';
    final rowFields = _childFields(f.kind, workspace.allows('financial_read'));
    return FormField<int>(
      initialValue: rows.length,
      validator: (_) => rows.isEmpty
          ? switch (f.kind) {
              'programme' => 'Add at least one fabric programme.',
              'entries' => 'Add at least one production line.',
              _ => 'Add at least one yarn input.',
            }
          : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.kind == 'inputs' && !identical(target, values))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(f.label, style: displayStyle(22)),
            ),
          for (final (i, row) in rows.indexed)
            Padding(
              key: ObjectKey(row),
              padding: const EdgeInsets.only(bottom: 12),
              child: _LineSheet(
                title: _rowTitle(f, row, i),
                onRemove: () => setState(() {
                  rows.removeAt(i);
                  changed = true;
                  state.didChange(rows.length);
                }),
                child: _grid(rowFields, row as Map<String, dynamic>),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              rows.add(<String, dynamic>{
                if (programme) ...{
                  'id': 'P${DateTime.now().microsecondsSinceEpoch}',
                  'knit_type': 'Tubular',
                },
              });
              changed = true;
              state.didChange(rows.length);
            }),
            icon: const Icon(Icons.add),
            label: Text(
              f.kind == 'entries'
                  ? 'Add production line'
                  : programme
                  ? 'Add fabric programme'
                  : 'Add yarn consumption',
            ),
          ),
          if (state.hasError)
            Text(
              state.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
