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
      body: Column(
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
                            _cover(true),
                            const SizedBox(height: 14),
                            child,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(flex: 3, child: _cover(false)),
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
                            Text(
                              stage,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
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
    );
  }

  Widget _cover(bool compact) {
    final detail = [
      company,
      if (job?['customer'] != null) job!['customer'],
      if (job?['name'] != null) job!['name'],
    ].join('  ·  ');
    final content = Padding(
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.title,
            style: displayStyle(compact ? 34 : 45, color: _paper),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: TextStyle(
              color: WorkspaceTheme.palePeach,
              height: 1.5,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
    Widget photo() => Image.asset(
      'assets/images/knitting-studio.jpg',
      fit: BoxFit.cover,
      alignment: const Alignment(.42, .32),
      excludeFromSemantics: true,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: WorkspaceTheme.charcoal,
        child: compact
            ? Stack(
                children: [
                  Positioned.fill(
                    left: 0,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: .38,
                        heightFactor: 1,
                        child: photo(),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            WorkspaceTheme.charcoal,
                            WorkspaceTheme.charcoal,
                            WorkspaceTheme.charcoal.withValues(alpha: .1),
                          ],
                          stops: const [0, .59, .98],
                        ),
                      ),
                    ),
                  ),
                  FractionallySizedBox(widthFactor: .74, child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 1.4, child: photo()),
                  content,
                ],
              ),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 22),
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: WorkspaceTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: displayStyle(26)),
        const SizedBox(height: 18),
        child,
      ],
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
