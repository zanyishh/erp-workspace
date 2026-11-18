import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'design.dart';
import 'erp_api.dart';
import 'knitting_models.dart';
import 'native_models.dart' show objectMap;
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';
import 'ui/access_gate.dart';
import 'ui/date_entry.dart';
import 'document_editor.dart';

part 'knitting_entry_layout.dart';
part 'knitting_batch_rows.dart';

String knittingProductionOperatorTitle(Map row) => [
  row['title']?.toString() ?? 'Original employee',
  if (row['employee_number']?.toString().trim().isNotEmpty == true)
    'Employee ${row['employee_number']}',
].join(' · ');

String knittingProductionMachineTitle(Map row) => [
  row['title']?.toString() ?? 'Original machine',
  if (row['machine_code']?.toString().trim().isNotEmpty == true)
    'Machine ${row['machine_code']}',
].join(' · ');

const originalProductionOperatorField = KnitField(
  'production_operator',
  'Production operator · original employee (optional)',
  kind: 'ProductionOperator',
  optional: true,
);
const originalProductionMachineField = KnitField(
  'production_machine',
  'Original machine (optional)',
  kind: 'ProductionMachine',
  optional: true,
);
const configuredProductionMachineField = KnitField(
  'machine',
  'Configured machine (optional)',
  kind: 'Machine',
  optional: true,
);

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
  String get command => id == 'revise_rate' ? 'revise_job' : id;

  IconData get icon => switch (id) {
    'create_job' => Icons.post_add_outlined,
    'revise_job' => Icons.edit_note_outlined,
    'revise_rate' => Icons.price_change_outlined,
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
    'produce_batch' => Icons.inventory_2_outlined,
    'produce_batches' => Icons.playlist_add_outlined,
    'produce_bulk' => Icons.layers_outlined,
    'split_roll' => Icons.call_split_rounded,
    'quality' => Icons.fact_check_outlined,
    'review_batch' => Icons.fact_check_outlined,
    'plan' => Icons.edit_calendar_outlined,
    'holiday' => Icons.event_busy_outlined,
    'deliver' => Icons.local_shipping_outlined,
    'deliver_batch' => Icons.local_shipping_outlined,
    'return_batch' => Icons.assignment_returned_outlined,
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
      (id != 'revise_rate' || workspace.allows('financial_read')) &&
      !workspace.unavailableKnittingActions.contains(id) &&
      !workspace.unavailableKnittingActions.contains(command);
  bool appearsIn(String destination) =>
      group == destination ||
      (id == 'revise_rate' && destination == 'Jobs') ||
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
const yarnReceiptReferences = [
  KnitField('source_lot', 'Supplier / customer lot', optional: true),
  KnitField('party_dc_number', 'Party challan number', optional: true),
  KnitField(
    'party_dc_date',
    'Party challan date',
    kind: 'date',
    optional: true,
  ),
];
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
    KnitField('delivery', 'Source delivery', kind: 'RollDelivery'),
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
    ...yarnReceiptReferences,
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
    KnitField(
      'billing_customer',
      'Bill to (optional)',
      kind: 'Customer',
      optional: true,
      finance: true,
    ),
    KnitField('job_date', 'Order date · YYYY-MM-DD', kind: 'date'),
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
  KnitAction('revise_rate', 'Revise rate', 'Billing', 'lifecycle', [
    KnitField('rate', 'Rate per kg', kind: 'money', finance: true),
    reasonField,
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
    ...yarnReceiptReferences,
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
    originalProductionOperatorField,
    configuredProductionMachineField,
    originalProductionMachineField,
    KnitField('shift', 'Shift'),
    weightsField,
    inputField,
    lossField,
    warehouseField,
  ]),
  KnitAction(
    'produce_batch',
    'Record batch production',
    'Production',
    'production',
    [
      lineField,
      originalProductionOperatorField,
      quantityField,
      KnitField('rolls', 'Recorded rolls / pieces', kind: 'integer'),
      inputField,
      lossField,
      configuredProductionMachineField,
      originalProductionMachineField,
      KnitField('shift', 'Shift'),
      warehouseField,
      KnitField('remarks', 'Remarks', optional: true),
    ],
  ),
  KnitAction(
    'produce_batches',
    'Record production rows',
    'Production',
    'production',
    [KnitField('entries', 'Production rows', kind: 'batch_rows')],
    needsJob: false,
  ),
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
  KnitAction('review_batch', 'Review fabric batch', 'Quality', 'quality', [
    KnitField('batch', 'Fabric batch', kind: 'Batch'),
    KnitField(
      'decision',
      'Decision',
      kind: 'select',
      options: ['Released', 'On Hold'],
    ),
    KnitField('remarks', 'Inspection notes'),
  ]),
  KnitAction('deliver_batch', 'Deliver fabric batch', 'Delivery', 'delivery', [
    KnitField('batch', 'Released fabric batch', kind: 'ReleasedBatch'),
    quantityField,
    KnitField('rolls', 'Roll count', kind: 'integer'),
    KnitField('destination', 'Delivery destination', optional: true),
    KnitField('transport', 'Transport / vehicle', optional: true),
    KnitField('transport_reference', 'Transport reference', optional: true),
  ]),
  KnitAction('return_batch', 'Receive batch return', 'Delivery', 'delivery', [
    KnitField('delivery', 'Source batch delivery', kind: 'BatchDelivery'),
    KnitField('batch', 'Fabric batch', kind: 'Batch'),
    quantityField,
    KnitField('rolls', 'Roll count', kind: 'integer'),
    reasonField,
  ]),
  KnitAction('deliver', 'Create delivery', 'Delivery', 'delivery', [
    KnitField('rolls', 'Released rolls', kind: 'Rolls'),
    KnitField('destination', 'Delivery destination', optional: true),
    KnitField('transport', 'Transport / vehicle', optional: true),
    KnitField('transport_reference', 'Transport reference', optional: true),
  ]),
  KnitAction('invoice', 'Bill delivered fabric', 'Billing', 'billing', [
    KnitField('deliveries', 'Confirmed deliveries', kind: 'Deliveries'),
    KnitField(
      'tax_template',
      'Sales tax template',
      kind: 'SalesTaxTemplate',
      optional: true,
      finance: true,
    ),
    KnitField(
      'no_tax',
      'No tax',
      kind: 'toggle',
      optional: true,
      finance: true,
    ),
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
    warehouseField,
    KnitField('shift', 'Machine shift', optional: true),
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
  bool get registerPicker => const {
    'Batch',
    'ReleasedBatch',
    'BatchDelivery',
    'RollDelivery',
  }.contains(widget.entity);
  int get pageSize => registerPicker ? 100 : 50;
  Future<Map<String, dynamic>> _load() async {
    if (!registerPicker) {
      return widget.api.knittingLookup(
        widget.company,
        widget.entity,
        query,
        start: start,
        job: widget.job,
      );
    }
    if (widget.job == null) {
      throw const ErpException('Choose the job before selecting its fabric.');
    }
    final batches =
        widget.entity == 'Batch' || widget.entity == 'ReleasedBatch';
    final collection = batches ? 'batches' : 'events';
    final response = await widget.api.knittingRegister(
      widget.company,
      collection,
      job: widget.job,
      start: start,
      query: query,
      state: widget.entity == 'ReleasedBatch' ? 'Released' : null,
    );
    final page = response['page'];
    final rows = response['rows'];
    if (response['version'] != 1 ||
        response['company'] != widget.company ||
        response['collection'] != collection ||
        response['scope_job'] != widget.job ||
        page is! Map ||
        page['start'] != start ||
        page['limit'] != 100 ||
        page['has_more'] is! bool ||
        rows is! List ||
        rows.length > 100 ||
        rows.any(
          (row) =>
              row is! Map || row['name'] is! String || row['job'] != widget.job,
        )) {
      throw const ErpException(
        'The fabric register returned an unexpected scope. Refresh and try again.',
      );
    }
    return {
      'rows': batches
          ? rows
          : rows
                .where(
                  (row) =>
                      row['kind'] ==
                          (widget.entity == 'BatchDelivery'
                              ? 'deliver_batch'
                              : 'deliver') &&
                      row['cancelled'] == 0 &&
                      (widget.entity != 'BatchDelivery' ||
                          row['result'] is Map &&
                              row['result']['batch'] is String),
                )
                .toList(),
      'has_more': page['has_more'],
    };
  }

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
    insetPadding:
        const {
              'ProductionOperator',
              'ProductionMachine',
            }.contains(widget.entity) &&
            MediaQuery.sizeOf(context).width < 500
        ? const EdgeInsets.all(12)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
          padding: EdgeInsets.all(
            const {
                      'ProductionOperator',
                      'ProductionMachine',
                    }.contains(widget.entity) &&
                    MediaQuery.sizeOf(context).width < 500
                ? 16
                : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Display(
                      'SELECT ${_entityLabel(widget.entity).toUpperCase()}',
                      size:
                          const {
                                'ProductionOperator',
                                'ProductionMachine',
                              }.contains(widget.entity) &&
                              MediaQuery.sizeOf(context).width < 500
                          ? 22
                          : 28,
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
                                          if (!const {
                                            'JobCustomer',
                                            'ProductionOperator',
                                            'ProductionMachine',
                                          }.contains(widget.entity))
                                            name,
                                          if (widget.entity ==
                                                  'ProductionOperator' &&
                                              row['employee_number']
                                                      ?.toString()
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true)
                                            'Employee ${row['employee_number']}',
                                          if (widget.entity ==
                                                  'ProductionMachine' &&
                                              row['machine_code']
                                                      ?.toString()
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true)
                                            'Machine ${row['machine_code']}',
                                          if (row['customer'] != null ||
                                              row['customer_name'] != null)
                                            knittingCustomerTitle(row),
                                          row['supplier'],
                                          row['item'],
                                          row['party'],
                                          row['category'],
                                          row['status'],
                                          row['state'],
                                          row['source_reference'],
                                          row['quantity_kg'] != null
                                              ? '${row['quantity_kg']} kg'
                                              : null,
                                          row['rolls'] != null
                                              ? '${row['rolls']} rolls'
                                              : null,
                                          if (row['result'] is Map) ...[
                                            row['result']['quantity_kg'] != null
                                                ? '${row['result']['quantity_kg']} kg'
                                                : null,
                                            row['result']['roll_count'] != null
                                                ? '${row['result']['roll_count']} rolls'
                                                : null,
                                            row['occurred_at'],
                                          ],
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
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton(
                                onPressed: start == 0
                                    ? null
                                    : () => setState(() {
                                        start -= pageSize;
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
                                        start += pageSize;
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
    this.initialReferences = const {},
    this.prepareOnly = false,
    this.onInvoicePreview,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final KnitAction action;
  final bool prepareOnly;
  final Future<void> Function(String name)? onInvoicePreview;
  final Map<String, dynamic>? job;
  final Map<String, dynamic> initial;
  final Map<String, Map<String, dynamic>> initialReferences;
  @override
  State<KnittingCommandForm> createState() => _KnittingCommandFormState();
}

class _KnittingCommandFormState extends State<KnittingCommandForm> {
  var formKey = GlobalKey<FormState>();
  var _guidedForms = List.generate(2, (_) => GlobalKey<FormState>());
  int _entryStep = 0;
  final values = <String, dynamic>{};
  final references = <String, Map<String, dynamic>>{};
  final recordLabels = <(String, String), String>{};
  final productionRowSources = <Map<String, dynamic>, Map<String, dynamic>>{};
  final scroll = ScrollController();
  KnittingDraft? draft;
  final preparedRequests = <String>{};
  late String account;
  bool review = false, changed = false, checkingTotals = false, leaving = false;
  bool refreshingSources = false;
  Map<String, dynamic>? invoiceReview;
  String? validation;
  bool accessInvalidatedDraft = false;
  Map<String, dynamic>? freshJob;
  WorkspaceContext get workspace =>
      widget.api.contextFor(widget.workspace.company!) ?? widget.workspace;
  Map<String, dynamic>? get job => freshJob ?? widget.job ?? references['job'];
  bool get importedProgrammeBlocked {
    if (widget.action.id != 'revise_job' || job == null) return false;
    if (job!.containsKey('is_imported')) return job!['is_imported'] == true;
    return job!['source_record']?.toString().isNotEmpty == true ||
        (job!['programme'] as List? ?? []).any(
          (line) =>
              line is Map &&
              line.keys.any((key) => key.toString().startsWith('source_')),
        );
  }

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
            'billing_customer',
            'rate',
            'charge_item',
            'charge_rate',
            'valuation_rate',
            'income_account',
            'expense_account',
            'tax_template',
            'no_tax',
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
  void didUpdateWidget(covariant KnittingCommandForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeAccessListener(_accountChanged);
      widget.api.addAccessListener(_accountChanged);
    }
    if (oldWidget.workspace.company != widget.workspace.company ||
        oldWidget.api != widget.api ||
        oldWidget.action.id != widget.action.id ||
        oldWidget.job?['name'] != widget.job?['name']) {
      final previous = draft;
      _resetEntryForms();
      values.clear();
      references.clear();
      recordLabels.clear();
      productionRowSources.clear();
      if (widget.action.needsJob && widget.job != null) {
        values['job'] = widget.job!['name'];
      }
      freshJob = null;
      refreshingSources = false;
      draft = null;
      review = false;
      accessInvalidatedDraft = false;
      final scope = oldWidget.workspace.company != widget.workspace.company
          ? 'Company'
          : 'Entry context';
      validation =
          previous?.state == CommandState.uncertain ||
              previous?.state == CommandState.posting
          ? '$scope changed. Check request ${previous!.requestId} in ${oldWidget.workspace.company} before posting it again.'
          : '$scope changed. Select current sources before reviewing.';
      account = widget.api.account;
    }
  }

  void _accountChanged() {
    if (!mounted || account == widget.api.account) return;
    account = widget.api.account;
    setState(() {
      _resetEntryForms();
      values.clear();
      references.clear();
      recordLabels.clear();
      productionRowSources.clear();
      if (widget.action.needsJob && widget.job != null) {
        values['job'] = widget.job!['name'];
      }
      freshJob = null;
      draft = null;
      review = false;
      invoiceReview = null;
      checkingTotals = refreshingSources = changed = false;
      validation = 'Account changed. Select current sources before entering data. Previous interrupted requests remain under the original account.';
    });
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accountChanged);
    scroll.dispose();
    super.dispose();
  }

  void _markDirty() => changed = true;
  void _updateProductionRows(VoidCallback update) => setState(update);

  void _resetEntryForms() {
    formKey = GlobalKey<FormState>();
    _guidedForms = List.generate(2, (_) => GlobalKey<FormState>());
    _entryStep = 0;
  }

  void _scrollToStart() {
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  List<KnitField> get fields => [
    if (widget.action.needsJob && widget.job == null) jobField,
    ...widget.action.fields.where(
      (f) =>
          !importedProgrammeBlocked &&
          (!f.finance || workspace.allows('financial_read')),
    ),
  ];
  @override
  void initState() {
    super.initState();
    account = widget.api.account;
    widget.api.addAccessListener(_accountChanged);
    for (final f in fields) {
      if (f.value != null) {
        values[f.key] = f.value;
      } else if (f.kind == 'select' && f.key != 'decision') {
        values[f.key] = f.options.first;
      }
    }
    if (widget.action.id == 'create_job') {
      values['job_date'] = DateTime.now().toIso8601String().substring(0, 10);
    }
    values.addAll(
      jsonDecode(jsonEncode(widget.initial)) as Map<String, dynamic>,
    );
    for (final entry in widget.initialReferences.entries) {
      references[entry.key] = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(entry.value)) as Map,
      );
    }
    final initialJob = references['job'];
    if (initialJob != null && initialJob['name'] is String) {
      recordLabels[('Job', initialJob['name'] as String)] = _recordTitle(
        initialJob,
        'Job',
      );
    }
    if (widget.action.id == 'revise_rate') {
      values.removeWhere(
        (key, _) => !const {'job', 'rate', 'reason'}.contains(key),
      );
    }
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
      if (const {'revise_job', 'revise_rate'}.contains(widget.action.id)) {
        values.remove('rate');
      }
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
              ? preparedRequests.contains(draft?.requestId)
                    ? 'This request is saved in Pending operations for ${workspace.company}. Check it there before posting another entry.'
                    : 'The result is not confirmed. Check or retry this same entry before leaving.'
              : 'Your unsaved entry will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          if (draft?.state != CommandState.uncertain ||
              preparedRequests.contains(draft?.requestId))
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                draft?.state == CommandState.uncertain
                    ? 'Leave and check later'
                    : 'Leave',
              ),
            ),
        ],
      ),
    );
    leaving = false;
    if (discard == true && mounted) Navigator.pop(context);
  }

  bool get _guidedEntry =>
      const {'create_job', 'create_estimate'}.contains(widget.action.id) &&
      workspaceUsesPhoneNavigation(context);

  List<String> get _entrySteps => [
    widget.action.id == 'create_job' ? 'Job brief' : 'Estimate details',
    'Fabric programme',
  ];

  Future<bool> _validateEntry({bool briefOnly = false}) async {
    final guided = _guidedEntry;
    final forms = guided ? _guidedForms : [formKey];
    for (final (index, form) in forms.indexed) {
      if (briefOnly && index > 0) break;
      final state = form.currentState;
      if (state == null) return false;
      final invalid = state.validateGranularly();
      if (invalid.isEmpty) continue;
      final errorContext = invalid.first.context;
      if (guided && index != _entryStep) {
        setState(() => _entryStep = index);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !errorContext.mounted) return false;
      }
      await Scrollable.ensureVisible(
        errorContext,
        duration: workspaceMotion(context),
        alignment: .2,
      );
      if (!mounted || !errorContext.mounted) return false;
      FocusNode? firstFocus;
      void visit(Element element) {
        if (firstFocus != null) return;
        if (element.widget case EditableText(:final focusNode)) {
          firstFocus = focusNode;
        } else {
          element.visitChildren(visit);
        }
      }

      errorContext.visitChildElements(visit);
      firstFocus?.requestFocus();
      return false;
    }
    return true;
  }

  Future<void> _nextEntryStep() async {
    final revision = widget.api.accessRevision;
    if (!await _validateEntry(briefOnly: true) ||
        !mounted ||
        revision != widget.api.accessRevision ||
        !widget.api.accessReady) {
      return;
    }
    _showEntryStep(1);
  }

  void _showEntryStep(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollToStart();
    setState(() {
      _entryStep = index;
      validation = null;
    });
  }

  Future<void> _review() async {
    if (importedProgrammeBlocked ||
        !widget.action.availableIn(workspace) ||
        !widget.api.accessReady ||
        draft?.state == CommandState.uncertain) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final validationRevision = widget.api.accessRevision;
    if (!await _validateEntry() ||
        !mounted ||
        !widget.api.accessReady ||
        validationRevision != widget.api.accessRevision ||
        review) {
      return;
    }
    try {
      if (widget.action.id == 'invoice') {
        final template =
            values['tax_template']?.toString().trim().isNotEmpty ?? false;
        final noTax = values['no_tax'] == true;
        if (template == noTax) {
          setState(
            () => validation =
                'Choose a sales tax template or explicitly select No tax.',
          );
          return;
        }
      }
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
      if (widget.action.id == 'save_master') values.remove('settings');
      if (values['master'] != null) {
        final source = references['master'];
        if (widget.action.id == 'save_master') {
          if (source == null ||
              source['name'] != values['master'] ||
              source['modified'] is! String ||
              (source['modified'] as String).isEmpty) {
            throw const ErpException(
              'Select the current definition again before reviewing.',
            );
          }
          final raw = source['specification'];
          final parsed = raw is String
              ? (raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw))
              : raw;
          if (parsed != null && parsed is! Map) {
            throw const ErpException(
              'The saved definition settings are unavailable.',
            );
          }
          final settings = Map<String, dynamic>.from(parsed as Map? ?? {});
          for (final key in [
            'description',
            'value',
            'severity',
            'boundary_kg',
          ]) {
            if (!values.containsKey(key) || values[key] == settings[key]) {
              continue;
            }
            if (values[key] == null || values[key] == '') {
              settings.remove(key);
            } else {
              settings[key] = values[key];
            }
          }
          values['settings'] = settings;
        }
        values['master_modified'] = source?['modified'];
      }
      if (values['quotation'] != null) {
        values['quotation_modified'] = references['quotation']?['modified'];
      }
      final frozen =
          Map<String, dynamic>.from(jsonDecode(jsonEncode(values)) as Map)
            ..removeWhere((k, v) => v == null || v == '')
            ..remove('preview_hash');
      if (widget.action.id == 'save_master') {
        frozen.remove('unit');
        frozen.remove('order');
      }
      draft = KnittingDraft(widget.action.command, frozen);
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
    if (id == 'produce_batches') return _productionRowsDiscrepancy();
    if (id == 'review_batch' && values['decision'] == 'Released') {
      final batch = references['batch'];
      if (batch != null &&
          (batch['quantity_kg'].toString().startsWith('-') ||
              batch['rolls'].toString().startsWith('-'))) {
        return 'Resolve the original negative stock balance before releasing this batch.';
      }
    }
    if (id == 'deliver_batch' ||
        id == 'return_batch' ||
        id == 'produce_batch') {
      if (Kg.parse(values['quantity_kg'].toString()).milli == BigInt.zero) {
        return 'Enter a positive fabric weight.';
      }
      if (id == 'return_batch' &&
          references['delivery']?['result']?['batch'] != null &&
          references['delivery']!['result']['batch'] != values['batch']) {
        return 'Choose the fabric batch from the selected delivery.';
      }
    }
    if (id == 'produce_batch' && job?['material_mode'] != 'Customer') {
      return 'Batch production supports customer-owned material only. Use individual rolls for owned or mixed stock.';
    }
    if (id == 'create_job' || id == 'create_estimate') {
      final target = Kg.parse(values['target_kg'].toString());
      final programme = total(
        (values['programme'] as List).map((row) => row['target_kg']),
      );
      if (target.compareTo(programme) != 0) {
        return 'The fabric programme totals $programme kg. Match it to the $target kg target before review.';
      }
    }
    if (const {
      'produce',
      'produce_bulk',
      'produce_batch',
      'subcontract_receive',
    }.contains(id)) {
      final entries = id == 'produce_bulk'
          ? values['entries'] as List
          : [values];
      for (final (i, row) in entries.indexed) {
        if (_hasValue(row['machine']) && _hasValue(row['production_machine'])) {
          return 'Choose either a configured machine or an original machine for each production row.';
        }
        final yarn = total(
          (row['inputs'] as List).map((input) => input['quantity_kg']),
        );
        final fabric = id == 'produce_batch'
            ? Kg.parse(row['quantity_kg'].toString())
            : total(row['weights_kg'] as List);
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
    final submitted =
        d.action == 'revise_job' && d.values.containsKey('programme')
        ? {
            ...d.values,
            'programme': [
              for (final row in d.values['programme'] as List)
                Map<String, dynamic>.from(row as Map)
                  ..remove('dia_display')
                  ..remove('dia_basis'),
            ],
          }
        : d.values;
    if (widget.prepareOnly) {
      if (sourceVersion == null || sourceVersion!.isEmpty || job == null) {
        setState(() {
          review = false;
          validation = 'Choose the current job before preparing this row.';
        });
        return;
      }
      Navigator.pop(context, <String, dynamic>{
        'values': jsonDecode(jsonEncode(submitted)),
        'modified': sourceVersion,
        'job': jsonDecode(jsonEncode(job)),
        'references': jsonDecode(jsonEncode(references)),
        'labels': Map<(String, String), String>.from(recordLabels),
      });
      return;
    }
    final api = widget.api, company = widget.workspace.company!;
    final epoch = api.accessRevision, account = api.account;
    final reviewedVersion = sourceVersion;
    final recoverable = api.supportsOperationRecovery(company);
    bool sent = false;
    final future = d.submit(() async {
      if (recoverable) {
        final operation = await api.beginOperation(
          company,
          'knitting',
          d.requestId,
          action: d.action,
        );
        preparedRequests.add(d.requestId);
        if (!mounted ||
            d != draft ||
            api != widget.api ||
            company != widget.workspace.company ||
            epoch != api.accessRevision ||
            account != api.account ||
            !api.accessReady) {
          throw const ErpException(
            'Access changed. Check this request after signing in.',
          );
        }
        if (operation['state'] == 'completed') {
          return objectMap(operation['result']);
        }
        if (operation['state'] != 'prepared') {
          throw const ErpException(
            'This request is closed. Check its status before editing.',
          );
        }
      }
      sent = true;
      final result = await api.knittingCommand(
        company,
        d.action,
        submitted,
        d.requestId,
        modified: reviewedVersion,
      );
      if (!mounted ||
          d != draft ||
          api != widget.api ||
          company != workspace.company ||
          epoch != api.accessRevision ||
          account != api.account ||
          !api.accessReady) {
        throw const ErpException(
          'Access changed while saving. Check the original request before posting again.',
        );
      }
      return result;
    });
    setState(() {});
    await future;
    if (!mounted || !identical(d, draft)) return;
    if (preparedRequests.contains(d.requestId) &&
        (d.state == CommandState.rejected || d.state == CommandState.stale)) {
      final rejectedState = d.state;
      setState(() => d.state = CommandState.checking);
      try {
        final closed = await api.closeOperation(company, d.requestId);
        if (!mounted ||
            d != draft ||
            api != widget.api ||
            company != workspace.company ||
            epoch != api.accessRevision ||
            account != api.account) {
          d.state = CommandState.uncertain;
          if (mounted && d == draft) setState(() {});
          return;
        }
        if (closed['state'] == 'completed') {
          d.result = objectMap(closed['result']);
          d.state = CommandState.confirmed;
          d.error = null;
        } else if (closed['state'] == 'closed') {
          d.state = rejectedState;
          try {
            await api.acknowledgeOperation(company, d.requestId);
          } catch (_) {}
        } else {
          d.state = CommandState.uncertain;
        }
      } catch (e) {
        d.state = CommandState.uncertain;
        d.error = '$e Check this request before posting again.';
      }
      if (!mounted || d != draft) return;
    }
    if (!sent &&
        !preparedRequests.contains(d.requestId) &&
        d.state == CommandState.uncertain) {
      // Preparation failed before the business request was sent. Keeping this
      // exact reference makes the next explicit attempt safe even if prepared.
      d.state = CommandState.editing;
    }
    setState(() {
      if (d.state == CommandState.rejected) {
        validation = d.error;
        review = false;
        draft = null;
        invoiceReview = null;
      }
    });
    if (d.state == CommandState.confirmed) _acknowledgeShown(d);
  }

  Future<void> _check() async {
    final d = draft;
    if (d == null) return;
    final api = widget.api, company = widget.workspace.company!;
    final epoch = api.accessRevision, account = api.account;
    final future = d.check(() async {
      final result = api.supportsOperationRecovery(company)
          ? await api.operationStatus(company, d.requestId)
          : await api.knittingCommandStatus(company, d.requestId);
      if (!mounted ||
          d != draft ||
          api != widget.api ||
          company != widget.workspace.company ||
          epoch != api.accessRevision ||
          account != api.account ||
          !api.accessReady) {
        throw const ErpException('Access changed. Check this request again.');
      }
      return result['state'] == 'completed'
          ? objectMap(result['result'])
          : result;
    });
    setState(() {});
    await future;
    if (mounted && identical(d, draft)) {
      setState(() {});
      if (d.state == CommandState.confirmed) _acknowledgeShown(d);
    }
  }

  void _acknowledgeShown(KnittingDraft d) {
    if (!preparedRequests.contains(d.requestId)) return;
    final api = widget.api, company = widget.workspace.company!;
    final owner = api.account, revision = api.accessRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          d != draft ||
          d.state != CommandState.confirmed ||
          !api.accessReady ||
          api.account != owner ||
          api.accessRevision != revision) {
        return;
      }
      try {
        await api.acknowledgeOperation(company, d.requestId);
      } catch (_) {}
    });
  }

  Future<void> _closeRequest() async {
    final d = draft;
    if (d == null || busy) return;
    final api = widget.api, company = widget.workspace.company!;
    final epoch = api.accessRevision, account = api.account;
    setState(() => d.state = CommandState.checking);
    try {
      final result = await api.closeOperation(company, d.requestId);
      if (!mounted ||
          d != draft ||
          api != widget.api ||
          company != widget.workspace.company ||
          epoch != api.accessRevision ||
          account != api.account ||
          !api.accessReady) {
        return;
      }
      if (result['state'] == 'completed') {
        setState(() {
          d.result = objectMap(result['result']);
          d.state = CommandState.confirmed;
          d.error = null;
        });
        _acknowledgeShown(d);
      } else if (result['state'] == 'closed') {
        try {
          await api.acknowledgeOperation(company, d.requestId);
        } catch (_) {}
        if (!mounted || d != draft) return;
        setState(() {
          review = false;
          draft = null;
          invoiceReview = null;
          accessInvalidatedDraft = false;
          validation = 'The request was closed without posting. Review your retained entry again.';
        });
      } else {
        setState(() => d.state = CommandState.uncertain);
      }
    } catch (e) {
      if (mounted && d == draft) {
        setState(() {
          d.error = e.toString();
          d.state = CommandState.uncertain;
        });
      }
    } finally {
      if (mounted && d == draft && d.state == CommandState.checking) {
        setState(() => d.state = CommandState.uncertain);
      }
    }
  }

  Future<void> _reloadStaleSources() async {
    if (busy || !widget.api.accessReady) return;
    final api = widget.api;
    final company = workspace.company!;
    final name = values['job'] as String?;
    final fixedJob = widget.job?['name'];
    final revision = api.accessRevision;
    bool sameSource() =>
        mounted &&
        identical(api, widget.api) &&
        company == workspace.company &&
        name == values['job'] &&
        fixedJob == widget.job?['name'];
    bool canApply() =>
        sameSource() && revision == api.accessRevision && api.accessReady;
    setState(() => refreshingSources = true);
    try {
      Map<String, dynamic>? latest;
      if (name != null) {
        final snapshot = await api.knittingSnapshot(company, job: name);
        latest = snapshot
            .rows('jobs')
            .where((j) => j['name'] == name)
            .firstOrNull;
        if (latest == null) {
          throw const ErpException('The source job is no longer available.');
        }
      }
      if (!canApply()) return;
      setState(() {
        freshJob = latest;
        for (final f in fields.where(
          (f) =>
              f.key != 'job' &&
              (_isPicker(f) ||
                  f.kind == 'line' ||
                  const {'entries', 'inputs', 'batch_rows'}.contains(f.kind)),
        )) {
          if (widget.action.id == 'save_master' && f.key == 'master') {
            references.remove(f.key);
          } else {
            values.remove(f.key);
            references.remove(f.key);
          }
        }
        if (widget.action.id == 'revise_job' && latest != null) {
          _loadProgramme(latest);
        }
        if (const {'revise_job', 'revise_rate'}.contains(widget.action.id)) {
          values.remove('rate');
        }
        invoiceReview = null;
        draft = null;
        review = false;
        validation = widget.action.id == 'revise_rate'
            ? 'Current job loaded. Enter the agreed rate again before reviewing.'
            : 'Current sources loaded. Check your programme and selections before reviewing again.';
      });
      _scrollToStart();
    } catch (e) {
      if (canApply()) setState(() => draft?.error = e.toString());
    } finally {
      if (sameSource()) setState(() => refreshingSources = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: AccessGate(
      key: ValueKey((
        widget.api,
        widget.workspace.company,
        widget.job?['name'],
      )),
      api: widget.api,
      revalidate: () async {
        final api = widget.api;
        final company = widget.workspace.company!;
        final selectedJob = values['job'];
        final fixedJob = widget.job?['name'];
        final revision = api.accessRevision;
        bool current() =>
            mounted &&
            identical(api, widget.api) &&
            company == widget.workspace.company &&
            selectedJob == values['job'] &&
            fixedJob == widget.job?['name'] &&
            revision == api.accessRevision &&
            api.accessReady;
        final effective = api.contextFor(company);
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
        values.remove('production_operator');
        values.remove('production_machine');
        if (widget.action.id == 'produce_batches') {
          values.remove('entries');
          productionRowSources.clear();
        }
        if (selectedJob != null) {
          final source = await api.knittingSnapshot(
            effective.company!,
            job: selectedJob as String,
          );
          if (!current()) return;
          final latest = source
              .rows('jobs')
              .where((r) => r['name'] == selectedJob)
              .firstOrNull;
          if (latest == null) {
            throw const ErpException('This source job is no longer available.');
          }
          freshJob = latest;
        }
        if (!current()) return;
        setState(() {
          review =
              draft?.state == CommandState.uncertain ||
              draft?.state == CommandState.posting ||
              draft?.state == CommandState.checking;
          validation = 'Access refreshed. Review the current sources and your retained entry again.';
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
        entrySteps: _guidedEntry ? _entrySteps : const [],
        entryStep: _entryStep,
        footer: _footer(),
        child: review
            ? _reviewPanel()
            : Form(
                key: formKey,
                onChanged: _markDirty,
                child: Panel(
                  padding: EdgeInsets.all(
                    workspaceUsesPhoneNavigation(context) ? 16 : 24,
                  ),
                  border: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (importedProgrammeBlocked)
                        const _EntrySection(
                          title: 'Original programme protected',
                          child: Text(
                            'Full programme revision is unavailable for imported jobs until original programme compatibility is supported. Use Revise rate to change the agreed rate while preserving the original programme.',
                          ),
                        ),
                      ..._entryGroups(),
                      if (const {
                        'produce',
                        'produce_bulk',
                        'produce_batch',
                        'produce_batches',
                      }.contains(widget.action.id))
                        ExpansionTile(
                          title: const Text('Production details'),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.action.id == 'produce_batches')
                              const Text(
                                'Each row records a job, fabric and actual yarn consumption. All rows post together at the current date and time.',
                              )
                            else if (widget.action.id == 'produce_batch')
                              const Text(
                                'Enter measured fabric weight, roll count and actual customer-owned yarn used. The batch posts at the current date and time without assigning individual roll weights.',
                              ),
                            if (widget.action.id != 'produce_batches')
                              const Text(
                                'Choose a configured machine or an original machine reference. Original references identify the machine without reserving capacity.',
                              ),
                            const Text(
                              'The signed-in account records the entry. The optional original employee identifies the production operator.',
                            ),
                          ],
                        ),
                      if (fields.isEmpty && !importedProgrammeBlocked)
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
    ),
  );
  List<Widget> _entryGroups() {
    final sections = _entrySections(widget.action, fields).entries;
    Widget section(MapEntry<String, List<KnitField>> group) =>
        _EntrySection(title: group.key, child: _grid(group.value, values));
    if (!_guidedEntry) return sections.map(section).toList();
    return [
      for (final (index, key) in _guidedForms.indexed)
        Offstage(
          offstage: _entryStep != index,
          child: ExcludeFocus(
            excluding: _entryStep != index,
            child: Form(
              key: key,
              onChanged: _markDirty,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in sections)
                    if ((group.key == _entrySteps.first) == (index == 0))
                      section(group),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget? _footer() {
    if (!review) {
      if (_guidedEntry && _entryStep == 0) {
        return FilledButton.icon(
          onPressed: _nextEntryStep,
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          label: const Text('Next'),
        );
      }
      final action = FilledButton.icon(
        onPressed: importedProgrammeBlocked ? null : _review,
        icon: const Icon(Icons.arrow_forward, size: 17),
        label: const Text('Review entry'),
      );
      return _guidedEntry
          ? Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _showEntryStep(0),
                  child: const Text('Back'),
                ),
                action,
              ],
            )
          : action;
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
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.sync),
            label: const Text('Check save status'),
          ),
          if (preparedRequests.contains(draft!.requestId))
            TextButton(
              onPressed: _closeRequest,
              child: const Text('Close unposted request'),
            )
          else
            TextButton(
              onPressed: () {
                draft!.state = CommandState.editing;
                _post();
              },
              child: const Text('Retry same entry'),
            ),
        ],
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
          child: Text(
            busy
                ? 'Waiting for ERP…'
                : widget.prepareOnly
                ? 'Use production row'
                : 'Confirm & post',
          ),
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
                  confirmed
                      ? 'SAVED IN ERP'
                      : widget.prepareOnly
                      ? 'REVIEW PRODUCTION ROW'
                      : 'REVIEW BEFORE POSTING',
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
            _invoiceReviewPanel(invoiceReview!),
            const SizedBox(height: 20),
          ],
          if (!confirmed) ...[
            if (const {
              'produce',
              'produce_bulk',
              'produce_batch',
              'produce_batches',
            }.contains(widget.action.id))
              Text('Recorded by · ${widget.api.userName}'),
            if (const {'produce', 'produce_batch'}.contains(widget.action.id) &&
                !_hasValue(d.values['production_operator']))
              const Text('Production operator · Unrecorded'),
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
              child: Semantics(
                liveRegion: true,
                child: Text(
                  d.state == CommandState.stale
                      ? '${d.error}\nReload the current sources and review your entry again.'
                      : '${d.error}\nCheck status before changing or posting this entry again.',
                  style: const TextStyle(color: Color(0xFFA23F38)),
                ),
              ),
            ),
          if (confirmed) ...[const SizedBox(height: 12), _savedOutcome(d)],
        ],
      ),
    );
  }

  Widget _invoiceReviewPanel(Map<String, dynamic> quote) {
    final currency = quote['currency']?.toString() ?? '';
    final precision = int.tryParse(quote['precision']?.toString() ?? '') ?? 2;
    final customer = quote['customer_name'] ?? quote['customer'];
    Widget amountRow(Widget label, Object? value, {bool total = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    formatInvoiceNumber(
                      value,
                      places: precision,
                      indian: currency == 'INR',
                    ),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    return Panel(
      border: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Display(
            currency.isEmpty ? 'Invoice totals' : 'Invoice totals · $currency',
            size: 26,
          ),
          if (customer != null && customer.toString().isNotEmpty)
            Text('Bill to · $customer'),
          if (quote['due_date'] != null)
            Text("Due date · ${quote['due_date']}"),
          if ((job?['balances'] as Map?)?['captured_delivered_kg'] != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Current agreed rate: original delivery references use the current programme price.',
              ),
            ),
          const Divider(height: 18),
          for (final row in (quote['items'] as List).whereType<Map>())
            amountRow(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['item'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "${formatInvoiceNumber(row['quantity'])} ${row['uom'] ?? ''} × ${formatInvoiceNumber(row['rate'])}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              row['amount'],
            ),
          const Divider(height: 18),
          amountRow(const Text('Net total'), quote['net_total']),
          for (final row
              in (quote['taxes'] as List? ?? const []).whereType<Map>())
            amountRow(Text(row['description'].toString()), row['amount']),
          if (quote['tax_total'] != null)
            amountRow(const Text('Tax total'), quote['tax_total']),
          if ((num.tryParse(quote['rounding_adjustment']?.toString() ?? '') ??
                  0) !=
              0)
            amountRow(const Text('Rounding'), quote['rounding_adjustment']),
          const Divider(height: 18),
          amountRow(
            const Text(
              'Total to post',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            quote['payable_total'] ?? quote['grand_total'],
            total: true,
          ),
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
            if (rolls == null && data['roll_count'] != null)
              _outcomeMetric('Rolls', '${data['roll_count']} rolls'),
            if (data['consumed_kg'] != null)
              _outcomeMetric('Yarn consumed', '${data['consumed_kg']} kg'),
            if (data['loss_kg'] != null)
              _outcomeMetric('Declared loss', '${data['loss_kg']} kg'),
            if (data['amount'] != null && workspace.allows('financial_read'))
              _outcomeMetric(
                'Document total',
                '${data['currency'] == null ? '' : "${data['currency']} "}${data['amount']}',
              ),
            if (data['status'] != null)
              _outcomeMetric('Status', data['status'].toString()),
            if (widget.action.id == 'produce_batches' &&
                data['entries'] is List)
              _outcomeMetric(
                'Production rows',
                '${(data['children'] as List).length} rows',
              ),
            if (data['completed'] is List)
              _outcomeMetric(
                'Completed jobs',
                '${(data['completed'] as List).length} jobs',
              ),
          ],
        ),
        if (widget.action.id == 'produce_batches' && data['children'] is List)
          for (final row in data['children'] as List)
            if (row is Map && row['batch'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText('Fabric batch · ${row['batch']}'),
              ),
        for (final (key, label) in [
          ('job', 'Job'),
          ('lot', 'Yarn lot'),
          ('batch', 'Fabric batch'),
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
        for (final (type, name) in sources) ...[
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
          if (type == 'Sales Invoice' &&
              data['can_print'] == true &&
              widget.onInvoicePreview != null &&
              workspace.readableRecords.contains('Sales Invoice'))
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => widget.onInvoicePreview!(name),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Preview invoice PDF'),
              ),
            ),
        ],
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
        if (f.kind == 'ProductionMachine') {
          final source = references[f.key];
          return known ??
              (source != null && source['name'] == id
                  ? knittingProductionMachineTitle(source)
                  : 'Original machine · select again to verify');
        }
        if (f.kind == 'ProductionOperator') {
          final source = references[f.key];
          final originalLabel = source != null && source['name'] == id
              ? knittingProductionOperatorTitle(source)
              : null;
          return known ??
              originalLabel?.toString() ??
              'Original employee · select again to verify';
        }
        if (known != null) return known;
        return MediaQuery.sizeOf(context).width < 600
            ? id.toString()
            : '${_entityLabel(_entityFor(f.kind))} · $id';
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
    if (f.kind == 'batch_rows') return _productionRowsReview(value as List);
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
                      if (widget.action.id == 'produce_bulk' &&
                          f.kind == 'entries' &&
                          !_hasValue(row['production_operator']))
                        const Text('Production operator · Unrecorded'),
                      for (final rf in [
                        ...descriptors,
                        if (f.kind == 'programme') ..._retainedProgrammeFields,
                      ])
                        if (_hasValue(row[rf.key]) &&
                            (f.kind != 'programme' || rf.key != 'fabric'))
                          _reviewField(
                            rf,
                            rf.key == 'dia'
                                ? knittingDiameterTitle(row)
                                : row[rf.key],
                          ),
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
    if (f.kind == 'batch_rows') return _productionRowsField(f, target);
    if (f.kind == 'toggle') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: target[f.key] == true || target[f.key] == 1,
        onChanged: (v) => setState(() {
          target[f.key] = v;
          if (f.key == 'no_tax' && v) {
            target.remove('tax_template');
            references.remove('tax_template');
          }
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
    if (f.kind == 'select' && f.options.length == 2 && f.key != 'decision') {
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
      final phone = MediaQuery.sizeOf(context).width < 600;
      void clear(FormFieldState<dynamic> state) {
        setState(() {
          if (f.key == 'job') _changeSourceJob(null);
          target.remove(f.key);
          if (identical(target, values)) references.remove(f.key);
          changed = true;
        });
        state.didChange(null);
      }

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
                final api = widget.api, company = workspace.company;
                final revision = api.accessRevision, sourceJob = values['job'];
                final row = await pickKnitRecord(
                  context,
                  widget.api,
                  widget.workspace.company!,
                  entity,
                  multiple: multi,
                  job: values['job'] as String?,
                );
                if (row != null &&
                    mounted &&
                    identical(api, widget.api) &&
                    company == workspace.company &&
                    revision == api.accessRevision &&
                    api.accessReady &&
                    sourceJob == values['job']) {
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
                    if (const {
                          'machine',
                          'production_machine',
                        }.contains(f.key) &&
                        const {
                          'produce',
                          'produce_batch',
                          'produce_bulk',
                        }.contains(widget.action.id)) {
                      final other = f.key == 'machine'
                          ? 'production_machine'
                          : 'machine';
                      target.remove(other);
                      if (identical(target, values)) references.remove(other);
                    }
                    for (final record
                        in multi ? row['records'] as List : [row]) {
                      final name = record['name'].toString();
                      final title = _recordTitle(record, entity);
                      recordLabels[(
                        f.kind,
                        name,
                      )] = f.kind == 'ProductionOperator'
                          ? knittingProductionOperatorTitle(record)
                          : f.kind == 'ProductionMachine'
                          ? knittingProductionMachineTitle(record)
                          : title == name
                          ? name
                          : '$title · $name';
                    }
                    if (identical(target, values)) references[f.key] = row;
                    if (f.key == 'tax_template') values['no_tax'] = false;
                    if (f.kind == 'BatchDelivery') {
                      values['batch'] = row['result']['batch'];
                      references.remove('batch');
                      recordLabels[('Batch', values['batch'].toString())] =
                          values['batch'].toString();
                    }
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
                      for (final key in [
                        'description',
                        'value',
                        'severity',
                        'boundary_kg',
                        'settings',
                        'unit',
                        'order',
                      ]) {
                        values.remove(key);
                      }
                      final raw = row['specification'];
                      final spec = raw is String
                          ? (raw.trim().isEmpty
                                ? <String, dynamic>{}
                                : jsonDecode(raw))
                          : raw;
                      values.addAll({
                        'title': row['title'],
                        'category': row['category'],
                        'enabled': row['enabled'] != 0,
                        for (final key in [
                          'description',
                          'value',
                          'severity',
                          'boundary_kg',
                        ])
                          if (spec is Map && spec.containsKey(key))
                            key: spec[key],
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
                  suffixIcon: phone && f.optional && _hasValue(target[f.key])
                      ? IconButton(
                          tooltip: 'Clear ${f.label}',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => clear(state),
                        )
                      : const Icon(Icons.search, size: 18),
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
            if (!phone && f.optional && target[f.key] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => clear(state),
                  child: const Text('Clear selection'),
                ),
              ),
          ],
        ),
      );
    }
    if (f.key == 'dia' &&
        target.containsKey('dia_display') &&
        target['dia_basis'] != 'physical') {
      return InputDecorator(
        decoration: InputDecoration(labelText: f.label),
        child: Text(knittingDiameterTitle(target)),
      );
    }
    if (f.kind == 'date' || f.kind == 'datetime') {
      final api = widget.api,
          company = workspace.company,
          revision = widget.api.accessRevision;
      final owner = api.account;
      return DateEntry(
        key: ValueKey((f.key, target, references['master']?['name'])),
        label: f.label,
        initialValue: target[f.key]?.toString() ?? '',
        withTime: f.kind == 'datetime',
        optional: f.optional,
        onChanged: (v) {
          if (mounted &&
              api == widget.api &&
              company == workspace.company &&
              owner == api.account &&
              revision == api.accessRevision &&
              api.accessReady) {
            target[f.key] = v;
          }
        },
      );
    }
    return TextFormField(
      key: ValueKey((
        f.key,
        references['master']?['name'],
        references['plan']?['name'],
        f.key == 'rate' && widget.action.id == 'revise_rate'
            ? (values['job'], sourceVersion)
            : _isRevisionRate(f)
            ? values['job']
            : null,
      )),
      initialValue: target[f.key]?.toString(),
      decoration: InputDecoration(
        labelText: f.label,
        helperText: _isRevisionRate(f)
            ? 'Leave blank to keep line rates. Enter a rate to apply it to every programme line.'
            : f.key == 'rate' && widget.action.id == 'revise_rate'
            ? 'Apply this agreed rate to every programme line.'
            : null,
        helperMaxLines: 3,
      ),
      maxLines: const {'notes', 'remarks', 'reason'}.contains(f.key) ? 2 : 1,
      keyboardType:
          [
            'kg',
            'money',
            'integer',
            'signed_kg',
            'signed_integer',
          ].contains(f.kind)
          ? TextInputType.numberWithOptions(
              decimal: !f.kind.contains('integer'),
              signed: f.kind.startsWith('signed_'),
            )
          : TextInputType.text,
      onChanged: (v) {
        target[f.key] = v;
        if (f.key == 'dia') {
          target.remove('dia_display');
          target.remove('dia_basis');
        }
      },
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
