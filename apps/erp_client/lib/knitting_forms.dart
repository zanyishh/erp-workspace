import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_api.dart';
import 'knitting_models.dart';
import 'workspace_context.dart';
import 'widgets.dart';
import 'ui/workspace_ui.dart';

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
}

const jobField = KnitField('job', 'Job', kind: 'Job');
const quantityField = KnitField('quantity_kg', 'Quantity · kg', kind: 'kg');
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
  KnitAction('revise_job', 'Revise programme', 'Jobs', 'new_job', [
    reasonField,
    programmeField,
    rateField,
  ]),
  KnitAction('close_job', 'Complete job', 'Jobs', 'lifecycle', []),
  KnitAction('reopen_job', 'Reopen job', 'Jobs', 'lifecycle', [reasonField]),
  KnitAction('receive_yarn', 'Receive yarn', 'Yarn', 'materials', [
    KnitField('item', 'Yarn item', kind: 'Item'),
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
  ]),
  KnitAction('allocate_yarn', 'Allocate general yarn', 'Yarn', 'materials', [
    lotField,
    quantityField,
  ]),
  KnitAction('transfer_yarn', 'Transfer to job', 'Yarn', 'materials', [
    lotField,
    quantityField,
    KnitField('target_job', 'Destination job', kind: 'Job'),
  ]),
  KnitAction('repack_yarn', 'Repack / process yarn', 'Yarn', 'materials', [
    lotField,
    KnitField('input_kg', 'Input · kg', kind: 'kg'),
    KnitField('output_kg', 'Output · kg', kind: 'kg'),
    lossField,
    KnitField('output_units', 'Output bags', kind: 'integer', value: '0'),
  ]),
  KnitAction('plan', 'Allocate machine', 'Planning', 'planning', [
    lineField,
    machineField,
    ...datesFields,
    quantityField,
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
    KnitField('remarks', 'Inspection notes'),
  ]),
  KnitAction('split_roll', 'Split roll', 'Production', 'production', [
    KnitField('roll', 'Original roll', kind: 'Roll'),
    weightsField,
    reasonField,
  ]),
  KnitAction('deliver', 'Create delivery', 'Delivery', 'delivery', [
    KnitField('rolls', 'Released rolls', kind: 'Rolls'),
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
    KnitField('event', 'Source delivery / invoice / QC', kind: 'Event'),
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
  KnitAction('create_subcontract', 'Subcontract order', 'Factory', 'factory', [
    KnitField('supplier', 'Supplier', kind: 'Supplier'),
    targetField,
    rateField,
    warehouseField,
  ]),
  KnitAction(
    'subcontract_issue',
    'Issue to subcontractor',
    'Factory',
    'materials',
    [
      KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
      lotField,
      quantityField,
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
    'Factory',
    'materials',
    [
      KnitField('subcontract', 'Subcontract', kind: 'Subcontract'),
      lotField,
      quantityField,
    ],
  ),
  KnitAction('subcontract_bill', 'Post supplier bill', 'Factory', 'billing', [
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
    warehouseField,
    KnitField('machine', 'Machine', kind: 'Machine', optional: true),
    reasonField,
  ], needsJob: false),
  KnitAction('return_consumable', 'Return consumable', 'Factory', 'factory', [
    KnitField('event', 'Original issue', kind: 'Event'),
    KnitField('quantity', 'Quantity', kind: 'kg'),
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
  late Future<Map<String, dynamic>> future = _load();
  Future<Map<String, dynamic>> _load() => widget.api.knittingLookup(
    widget.company,
    widget.entity,
    query,
    start: start,
  );
  @override
  Widget build(BuildContext context) => Dialog(
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
                    'SELECT ${widget.entity.toUpperCase()}',
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
              onSubmitted: (v) => setState(() {
                query = v;
                start = 0;
                future = _load();
              }),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: future,
                builder: (c, s) {
                  if (s.hasError) {
                    return MessagePanel(
                      title: 'COULD NOT LOAD',
                      message: s.error.toString(),
                      action: () => setState(() => future = _load()),
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
                            ? const Center(child: Text('No matching records.'))
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
                                      row['title']?.toString() ?? name,
                                    ),
                                    subtitle: Text(
                                      [
                                        name,
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
                          Text('${start + 1}–${start + rows.length}'),
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
                      }),
                child: Text('Use ${selected.length} selected'),
              ),
          ],
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
  KnittingDraft? draft;
  bool review = false, changed = false;
  String? validation;
  late List<KnitField> fields = [
    if (widget.action.needsJob && widget.job == null) jobField,
    ...widget.action.fields.where(
      (f) => !f.finance || widget.workspace.allows('financial_read'),
    ),
  ];
  @override
  void initState() {
    super.initState();
    for (final f in fields) {
      if (f.value != null) {
        values[f.key] = f.value;
      } else if (f.kind == 'select') {
        values[f.key] = f.options.first;
      }
    }
    values.addAll(widget.initial);
    if (widget.job != null) {
      values['job'] = widget.job!['name'];
      if (widget.action.id == 'revise_job') {
        values['programme'] = List<Map<String, dynamic>>.from(
          (widget.job!['programme'] as List).map(
            (r) => Map<String, dynamic>.from(r),
          ),
        );
        values['rate'] = widget.job!['rate'];
      }
    }
  }

  bool get busy =>
      draft?.state == CommandState.posting ||
      draft?.state == CommandState.checking;
  Future<bool> _leave() async {
    if (!changed || draft?.state == CommandState.confirmed) return true;
    return await showDialog<bool>(
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
        ) ??
        false;
  }

  void _review() {
    if (!formKey.currentState!.validate()) return;
    try {
      for (final f in fields.where(
        (f) => [
          'programme',
          'inputs',
          'weights',
          'Rolls',
          'Deliveries',
        ].contains(f.kind),
      )) {
        if ((values[f.key] as List? ?? []).isEmpty) {
          throw FormatException('Add ${f.label.toLowerCase()}.');
        }
      }
      if (values['target_job'] != null) {
        values['target_modified'] = references['target_job']?['modified'];
      }
      if (values['quotation'] != null) {
        values['quotation_modified'] = references['quotation']?['modified'];
      }
      values.removeWhere((k, v) => v == null || v == '');
      draft = KnittingDraft(widget.action.id, values);
      setState(() {
        review = true;
        validation = null;
      });
    } catch (e) {
      setState(() => validation = e.toString());
    }
  }

  Future<void> _post() async {
    final d = draft!;
    final modified = widget.job?['modified'] ?? references['job']?['modified'];
    final future = d.submit(
      () => widget.api.knittingCommand(
        widget.workspace.company!,
        d.action,
        d.values,
        d.requestId,
        modified: modified as String?,
      ),
    );
    setState(() {});
    await future;
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !changed || draft?.state == CommandState.confirmed,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && await _leave() && context.mounted) {
        setState(() => changed = false);
        if (context.mounted) Navigator.pop(context);
      }
    },
    child: WorkspacePage(
      title: widget.action.title,
      subtitle:
          '${widget.workspace.company} · ${widget.job?['name'] ?? 'Knitting'}',
      actions: [
        if (!review)
          FilledButton(onPressed: _review, child: const Text('Review entry')),
      ],
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: review
                ? _reviewPanel()
                : Form(
                    key: formKey,
                    onChanged: () => changed = true,
                    child: Panel(
                      border: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'SOURCE & DETAILS',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 20),
                          for (final f in fields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: _field(f, values),
                            ),
                          if (validation != null)
                            Text(
                              validation!,
                              style: const TextStyle(color: Colors.red),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  Widget _reviewPanel() {
    final d = draft!;
    final confirmed = d.state == CommandState.confirmed;
    return Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                confirmed
                    ? Icons.check_circle_outline
                    : Icons.fact_check_outlined,
                color: confirmed ? const Color(0xFF3E6B54) : WorkspaceTheme.ink,
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
                ? 'The server confirmed this action. Source records are available in the job activity.'
                : 'Check the source, ownership and quantities. Confirming will write to this company’s ERP.',
          ),
          const SizedBox(height: 20),
          for (final e in d.values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      _label(e.key),
                      style: const TextStyle(color: WorkspaceTheme.muted),
                    ),
                  ),
                  Expanded(child: Text(_readable(e.value))),
                ],
              ),
            ),
          const Divider(height: 32),
          SelectableText(
            'Request ${d.requestId}',
            style: const TextStyle(fontSize: 11, color: WorkspaceTheme.muted),
          ),
          if (d.error != null && !confirmed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${d.error}\nCheck status before changing or posting this entry again.',
                style: const TextStyle(color: Color(0xFFA23F38)),
              ),
            ),
          if (confirmed) ...[
            const SizedBox(height: 12),
            SelectableText(_readable(d.result)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ] else if (d.state == CommandState.uncertain)
            FilledButton.icon(
              onPressed: _check,
              icon: const Icon(Icons.sync),
              label: const Text('Check save status'),
            )
          else
            Row(
              children: [
                if (!busy)
                  TextButton(
                    onPressed: () => setState(() {
                      review = false;
                      draft = null;
                    }),
                    child: const Text('Edit entry'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: busy ? null : _post,
                  child: Text(busy ? 'Waiting for ERP…' : 'Confirm & post'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _label(String key) => key.replaceAll('_', ' ');
  String _readable(dynamic value) {
    if (value is Map) {
      return value.entries
          .map((e) => '${_label(e.key.toString())}: ${_readable(e.value)}')
          .join('\n');
    }
    if (value is List) return value.map(_readable).join('\n');
    return value?.toString() ?? '—';
  }

  Widget _field(KnitField f, Map<String, dynamic> target) {
    if (['programme', 'inputs'].contains(f.kind)) return _rowsField(f, target);
    if (f.kind == 'weights') {
      return TextFormField(
        initialValue: (target[f.key] as List? ?? []).join(', '),
        decoration: InputDecoration(
          labelText: f.label,
          helperText: 'Separate each roll with a comma. Example: 24, 25.500',
        ),
        onChanged: (v) => target[f.key] = v
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        validator: (v) {
          try {
            if (f.optional && (v ?? '').trim().isEmpty) return null;
            for (final x in (v ?? '').split(',')) {
              Kg.parse(x.trim());
            }
            return null;
          } catch (_) {
            return 'Enter valid individual kg, up to 3 decimal places.';
          }
        },
      );
    }
    if (f.kind == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: target[f.key]?.toString() ?? f.options.first,
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
      final job = widget.job ?? references['job'];
      final lines = (job?['programme'] as List? ?? []);
      return DropdownButtonFormField<String>(
        initialValue: target[f.key] as String?,
        decoration: InputDecoration(
          labelText: f.label,
          helperText: lines.isEmpty ? 'Select a job first.' : null,
        ),
        items: lines
            .map(
              (r) => DropdownMenuItem<String>(
                value: r['id'] as String,
                child: Text(
                  '${r['id']} · ${r['fabric']} · ${r['target_kg']} kg',
                ),
              ),
            )
            .toList(),
        onChanged: (v) => target[f.key] = v,
        validator: (v) => v == null ? 'Choose a programme line.' : null,
      );
    }
    if (![
      'text',
      'kg',
      'money',
      'integer',
      'date',
      'datetime',
    ].contains(f.kind)) {
      final multi = ['Rolls', 'Deliveries'].contains(f.kind);
      final entity = switch (f.kind) {
        'Rolls' => 'ReleasedRoll',
        'Deliveries' => 'Delivery',
        _ => f.kind,
      };
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
            OutlinedButton(
              onPressed: () async {
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
                    target[f.key] = multi ? row['names'] : row['name'];
                    references[f.key] = row;
                    changed = true;
                  });
                  state.didChange(target[f.key]);
                }
              },
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(17),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${f.label}\n${target[f.key] is List ? (target[f.key] as List).join(', ') : target[f.key] ?? 'Choose a record'}',
                    ),
                  ),
                  const Icon(Icons.search, size: 18),
                ],
              ),
            ),
            if (f.optional && target[f.key] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => target.remove(f.key)),
                  child: const Text('Clear'),
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
    return TextFormField(
      initialValue: target[f.key]?.toString(),
      decoration: InputDecoration(labelText: f.label),
      maxLines: f.key == 'notes' || f.key == 'remarks' ? 3 : 1,
      keyboardType: ['kg', 'money', 'integer'].contains(f.kind)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (v) => target[f.key] = v,
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return f.optional ? null : 'Enter ${f.label.toLowerCase()}.';
        }
        try {
          if (f.kind == 'kg') {
            Kg.parse(v);
          }
          if (f.kind == 'money' && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)) {
            return 'Use up to two decimal places.';
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

  Widget _rowsField(KnitField f, Map<String, dynamic> target) {
    final rows = (target[f.key] ??= <Map<String, dynamic>>[]) as List;
    final programme = f.kind == 'programme';
    final rowFields = programme
        ? const [
            KnitField('fabric', 'Fabric'),
            KnitField('colour', 'Colour', optional: true),
            KnitField('yarn_count', 'Yarn count', optional: true),
            KnitField('dia', 'Dia', optional: true),
            KnitField('gauge', 'Gauge', optional: true),
            KnitField(
              'knit_type',
              'Knit type',
              kind: 'select',
              options: ['Tubular', 'Open width'],
            ),
            targetField,
            KnitField(
              'fabric_item',
              'Fabric stock item',
              kind: 'Item',
              optional: true,
            ),
            KnitField(
              'gsm',
              'GSM · up to 2 values',
              kind: 'weights',
              optional: true,
            ),
            KnitField(
              'll',
              'Loop length · up to 3 values',
              kind: 'weights',
              optional: true,
            ),
          ]
        : [
            lotField,
            quantityField,
            if (widget.workspace.allows('financial_read')) ...const [
              KnitField(
                'charge_item',
                'Separate owned material charge item',
                kind: 'Item',
                optional: true,
                finance: true,
              ),
              KnitField(
                'charge_rate',
                'Charge rate',
                kind: 'money',
                optional: true,
                finance: true,
              ),
            ],
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Display(f.label.toUpperCase(), size: 25),
        const SizedBox(height: 12),
        for (final (i, row) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              key: ObjectKey(row),
              border: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          programme
                              ? 'Programme ${row['id']}'
                              : 'Input ${i + 1}',
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => rows.removeAt(i)),
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove row',
                      ),
                    ],
                  ),
                  for (final rf in rowFields)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _field(rf, row as Map<String, dynamic>),
                    ),
                ],
              ),
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
          }),
          icon: const Icon(Icons.add),
          label: Text(
            programme ? 'Add fabric programme' : 'Add yarn consumption',
          ),
        ),
      ],
    );
  }
}
