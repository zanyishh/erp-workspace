part of 'knitting_forms.dart';

const _paper = Color(0xFFFAF8F3);
const _sheet = Color(0xFFF1EEE7);
const _nestedKinds = {'programme', 'entries', 'inputs'};

String _entityFor(String kind) => switch (kind) {
  'Rolls' => 'ReleasedRoll',
  'Jobs' => 'ClosingJob',
  'UndeliveredRolls' => 'Roll',
  'DeliveredRolls' => 'DeliveredRoll',
  'Defects' => 'Defect',
  'Deliveries' => 'Delivery',
  _ => kind,
};

String _entityLabel(String entity) => switch (entity) {
  'ClosingJob' => 'running job',
  'ReleasedRoll' => 'released roll',
  'LabelRoll' => 'roll',
  'DeliveredRoll' => 'delivered roll',
  'YarnReceipt' => 'yarn receipt',
  'InvoiceEvent' => 'invoice',
  'PurchaseOrder' => 'yarn order',
  'CompanyEvent' => 'company record',
  'Event' => 'source record',
  'ConsumableIssue' => 'consumable issue',
  'CompletedSubcontract' => 'completed subcontract',
  'Master' => 'definition',
  'Plan' => 'machine allocation',
  _ => entity.toLowerCase(),
};

bool _isPicker(KnitField f) => !const {
  'text',
  'select',
  'line',
  'toggle',
  'signed_kg',
  'kg',
  'money',
  'integer',
  'signed_integer',
  'date',
  'datetime',
  'weights',
  'measurements',
  ..._nestedKinds,
}.contains(f.kind);

String _recordTitle(Map row, String entity) {
  for (final key in [
    'title',
    'customer',
    'supplier',
    'item',
    'party_name',
    'component_type',
    'machine',
  ]) {
    final title = row[key]?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
  }
  if (row['weight_kg'] != null) return 'Roll · ${row['weight_kg']} kg';
  if (row['kind'] != null) return row['kind'].toString().replaceAll('_', ' ');
  if (entity == 'Warehouse') return row['name'].toString();
  return _entityLabel(entity);
}

String _programmeName(Map row, int i) => [
  if ((row['fabric'] as String? ?? '').isNotEmpty)
    row['fabric']
  else
    'Fabric ${i + 1}',
  if ((row['colour'] as String? ?? '').isNotEmpty) row['colour'],
  if (row['target_kg'] != null) '${row['target_kg']} kg',
].join(' · ');

const _retainedProgrammeFields = [
  KnitField('finish_dia', 'Finished dia'),
  KnitField('finish_gsm', 'Finished GSM'),
  KnitField('brand', 'Brand'),
  KnitField('construct', 'Construction'),
  KnitField('organic', 'Organic'),
  KnitField('regenagri', 'Regenagri'),
];

Map<String, List<KnitField>> _entrySections(
  KnitAction action,
  List<KnitField> fields,
) {
  final sections = <String, List<KnitField>>{};
  for (final field in fields) {
    final section = switch (field.key) {
      'programme' || 'entries' || 'inputs' => field.label,
      'reason' || 'notes' || 'remarks' => 'Notes & instructions',
      'customer' ||
      'kind' ||
      'due_date' ||
      'material_mode' ||
      'target_kg' when action.id == 'create_job' => 'Job brief',
      'customer' ||
      'material_mode' ||
      'target_kg' when action.id == 'create_estimate' => 'Estimate details',
      'material_owner' ||
      'party' ||
      'item' ||
      'purchase_order' ||
      'source_lot' when action.id == 'receive_yarn' => 'Yarn & ownership',
      'starts_at' ||
      'ends_at' ||
      'shift' ||
      'date' ||
      'due_date' ||
      'effective_from' => 'Timing',
      'rate' || 'charge_item' || 'charge_rate' || 'valuation_rate' => 'Pricing',
      'material_owner' || 'material_mode' || 'party' => 'Material ownership',
      'weights_kg' ||
      'loss_kg' ||
      'quantity_kg' ||
      'quantity' ||
      'target_kg' ||
      'required_yarn_kg' ||
      'units' ||
      'input_units' ||
      'output_units' ||
      'input_kg' ||
      'output_kg' => 'Quantities',
      'transport' ||
      'transport_reference' ||
      'destination' => 'Dispatch details',
      'decision' || 'defects' => 'Inspection',
      'job' ||
      'jobs' ||
      'lot' ||
      'item' ||
      'source_lot' ||
      'purchase_order' ||
      'warehouse' ||
      'target_warehouse' ||
      'event' ||
      'subcontract' ||
      'receipt' ||
      'target_job' ||
      'target_programme_line' ||
      'invoice_event' ||
      'delivery' ||
      'deliveries' ||
      'roll' ||
      'rolls' ||
      'quotation' => 'Source & destination',
      _ => switch (action.group) {
        'Jobs' => 'Job details',
        'Factory' => 'Factory details',
        'Planning' || 'Production' => 'Machine & programme',
        'Billing' => 'Commercial details',
        _ => 'Entry details',
      },
    };
    (sections[section] ??= []).add(field);
  }
  // Keep references ahead of quantities and put remarks at the end of the entry.
  return {
    for (final title in [
      'Source & destination',
      ...sections.keys.where(
        (s) => s != 'Source & destination' && s != 'Notes & instructions',
      ),
      'Notes & instructions',
    ])
      if (sections.containsKey(title)) title: sections[title]!,
  };
}

class _EntryPage extends StatelessWidget {
  const _EntryPage({
    required this.company,
    required this.action,
    required this.job,
    required this.scroll,
    required this.review,
    required this.confirmed,
    required this.child,
    required this.footer,
    this.error,
  });
  final String company;
  final KnitAction action;
  final Map<String, dynamic>? job;
  final ScrollController scroll;
  final bool review, confirmed;
  final Widget child;
  final Widget? footer;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 850;
    final stage = confirmed
        ? 'Posted'
        : review
        ? 'Review'
        : 'Entry';
    return Scaffold(
      backgroundColor: _sheet,
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: _sheet,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_outlined, size: 16),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                'Knitting  /  ${action.group}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  color: WorkspaceTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: WorkspaceBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: EdgeInsets.all(narrow ? 14 : 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1250),
                    child: narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _cover(context, true),
                              const SizedBox(height: 14),
                              child,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(flex: 3, child: _cover(context, false)),
                              const SizedBox(width: 24),
                              Expanded(flex: 7, child: child),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (error != null)
              Material(
                color: const Color(0xFFFBE9DB),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFF842E20)),
                    semanticsLabel: error,
                  ),
                ),
              ),
            if (footer != null)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: _paper,
                  border: Border(top: BorderSide(color: WorkspaceTheme.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: narrow ? 16 : 32,
                      vertical: 9,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1250),
                        child: Row(
                          children: [
                            if (MediaQuery.sizeOf(context).width >= 460) ...[
                              Icon(
                                confirmed
                                    ? Icons.check_circle_outline
                                    : review
                                    ? Icons.fact_check_outlined
                                    : Icons.edit_outlined,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              AnimatedSwitcher(
                                duration: workspaceMotion(context),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                child: Text(
                                  stage,
                                  key: ValueKey(stage),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: footer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, bool compact) {
    final detail = [
      company,
      if (job?['customer'] != null) job!['customer'],
      if (job?['name'] != null) job!['name'],
    ].join('  ·  ');
    final alignment = switch (action.group) {
      'Yarn' => Alignment.centerLeft,
      'Factory' || 'Planning' || 'Production' => Alignment.centerRight,
      _ => Alignment.center,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/knitting-studio.jpg',
              fit: BoxFit.cover,
              alignment: alignment,
              excludeFromSemantics: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, compact ? 28 : 132, 10, 10),
            child: Panel(
              dark: true,
              frosted: true,
              radius: 13,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 12 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    action.title,
                    style: displayStyle(
                      compact ? 30 : 37,
                      color: WorkspaceTheme.light,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: WorkspaceTheme.palePeach,
                      height: 1.45,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      label: confirmed
                          ? 'Entry posted'
                          : review
                          ? 'Review before posting'
                          : 'Editing entry',
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i == 2 ? 0 : 4,
                                  ),
                                  child: AnimatedContainer(
                                    duration: workspaceMotion(context),
                                    height: 3,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color:
                                          i <=
                                              (confirmed
                                                  ? 2
                                                  : review
                                                  ? 1
                                                  : 0)
                                          ? WorkspaceTheme.palePeach
                                          : const Color(0xFF5C6862),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Entry', style: TextStyle(fontSize: 11)),
                        Text('Review', style: TextStyle(fontSize: 11)),
                        Text('Posted', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.fields, required this.buildField});
  final List<KnitField> fields;
  final Widget Function(KnitField) buildField;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final half = (c.maxWidth - 14) / 2;
      return Wrap(
        spacing: 14,
        runSpacing: 16,
        children: [
          for (final f in fields)
            SizedBox(
              key: ValueKey(f.key),
              width:
                  half >= 235 &&
                      fields.length > 1 &&
                      !_nestedKinds.contains(f.kind) &&
                      !const {'reason', 'notes', 'remarks'}.contains(f.key)
                  ? half
                  : c.maxWidth,
              child: buildField(f),
            ),
        ],
      );
    },
  );
}

class _EntrySection extends StatelessWidget {
  const _EntrySection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      radius: 17,
      border: true,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: displayStyle(26)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class _LineSheet extends StatelessWidget {
  const _LineSheet({required this.title, required this.child, this.onRemove});
  final String title;
  final Widget child;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _sheet,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 3, height: 19, color: WorkspaceTheme.peach),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: displayStyle(23))),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove row',
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

List<KnitField> _childFields(String kind, bool finance) => kind == 'entries'
    ? const [
        lineField,
        machineField,
        KnitField('shift', 'Shift'),
        weightsField,
        inputField,
        lossField,
        warehouseField,
      ]
    : kind == 'programme'
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
          kind: 'measurements',
          optional: true,
        ),
        KnitField(
          'll',
          'Loop length · up to 3 values',
          kind: 'measurements',
          optional: true,
        ),
      ]
    : [
        lotField,
        quantityField,
        unitsField,
        if (finance) ...const [
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
