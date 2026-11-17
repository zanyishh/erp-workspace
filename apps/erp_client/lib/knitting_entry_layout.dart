part of 'knitting_forms.dart';

const _paper = WorkspaceTheme.surface;
const _sheet = WorkspaceTheme.canvas;
const _nestedKinds = {'programme', 'entries', 'inputs', 'batch_rows'};

String _entityFor(String kind) => switch (kind) {
  'Rolls' => 'ReleasedRoll',
  'Jobs' => 'ClosingJob',
  'UndeliveredRolls' => 'Roll',
  'DeliveredRolls' => 'DeliveredRoll',
  'Defects' => 'Defect',
  'Deliveries' => 'BillingDelivery',
  _ => kind,
};

String _entityLabel(String entity) => switch (entity) {
  'JobCustomer' => 'Customer',
  'ProductionOperator' => 'operator',
  'ProductionMachine' => 'machine',
  'StockKgItem' => 'stock item measured in kg',
  'ServiceItem' => 'non-stock item',
  'ClosingJob' => 'running job',
  'ReleasedRoll' => 'released roll',
  'LabelRoll' => 'roll',
  'DeliveredRoll' => 'delivered roll',
  'Batch' => 'fabric batch',
  'ReleasedBatch' => 'released fabric batch',
  'BatchDelivery' => 'batch delivery',
  'RollDelivery' => 'roll delivery',
  'BillingDelivery' => 'delivery available for billing',
  'SalesTaxTemplate' => 'sales tax template',
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
  if ((entity == 'Job' || entity == 'ClosingJob') &&
      ((row['source_reference_display']?.toString().trim().isNotEmpty ??
              false) ||
          (row['source_reference']?.toString().trim().isNotEmpty ?? false))) {
    return knittingJobTitle(Map<String, dynamic>.from(row));
  }
  for (final key in [
    'title',
    'customer_name',
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
  if (entity == 'Batch' || entity == 'ReleasedBatch') return 'Fabric batch';
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
  if (row.containsKey('dia_display') || row['dia'] != null)
    '${knittingDiameterTitle(row)} dia',
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
  final receipt = action.id == 'receive_yarn';
  final sections = <String, List<KnitField>>{};
  for (final field in fields) {
    final section = switch (field.key) {
      'job' ||
      'item' ||
      'quantity_kg' ||
      'units' when receipt => 'Yarn received',
      'material_owner' ||
      'party' ||
      'warehouse' when receipt => 'Ownership & storage',
      'source_lot' ||
      'party_dc_number' ||
      'party_dc_date' ||
      'purchase_order' when receipt => 'Receipt references',
      'programme' || 'entries' || 'inputs' => field.label,
      'reason' || 'notes' || 'remarks' => 'Notes & instructions',
      'customer' ||
      'billing_customer' ||
      'job_date' ||
      'kind' ||
      'due_date' ||
      'material_mode' ||
      'target_kg' when action.id == 'create_job' => 'Job brief',
      'customer' ||
      'material_mode' ||
      'target_kg' when action.id == 'create_estimate' => 'Estimate details',
      'starts_at' ||
      'ends_at' ||
      'shift' ||
      'date' ||
      'due_date' ||
      'effective_from' => 'Timing',
      'rate' || 'charge_item' || 'charge_rate' || 'valuation_rate' => 'Pricing',
      'tax_template' || 'no_tax' => 'Invoice tax',
      'material_owner' || 'material_mode' || 'party' => 'Material ownership',
      'weights_kg' ||
      'loss_kg' ||
      'quantity_kg' ||
      'quantity' ||
      'rolls' ||
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
      'batch' ||
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
  final titles = <String>{
    'Source & destination',
    if (receipt) ...[
      'Yarn received',
      'Ownership & storage',
      'Receipt references',
    ],
    ...sections.keys.where((s) => s != 'Notes & instructions'),
    'Notes & instructions',
  };
  return {
    for (final title in titles)
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
    final width = MediaQuery.sizeOf(context).width;
    final phone = workspaceUsesPhoneNavigation(context);
    final narrow = phone || width < 850;

    return Scaffold(
      backgroundColor: _sheet,
      appBar: AppBar(
        toolbarHeight: phone ? null : 48,
        backgroundColor: _sheet,
        title: phone
            ? Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 20),
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
        child: SafeArea(
          top: false,
          bottom: footer == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: phone
                      ? ScrollViewKeyboardDismissBehavior.onDrag
                      : ScrollViewKeyboardDismissBehavior.manual,
                  controller: scroll,
                  padding: EdgeInsets.all(narrow ? 14 : 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1140),
                      child: narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _cover(context, true, phone: phone),
                                const SizedBox(height: 14),
                                child,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  flex: 3,
                                  child: _cover(context, false),
                                ),
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
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFF842E20)),
                        semanticsLabel: error,
                      ),
                    ),
                  ),
                ),
              if (footer != null)
                Panel(
                  frosted: true,
                  padding: EdgeInsets.zero,
                  radius: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: narrow ? 16 : 32,
                        vertical: 9,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1140),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: phone
                                ? SizedBox(
                                    width: double.infinity,
                                    child: footer,
                                  )
                                : footer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageProgress(BuildContext context, int stage, {bool dark = false}) =>
      TweenAnimationBuilder<double>(
        tween: Tween(end: (stage + 1) / 3),
        curve: Curves.easeOutCubic,
        duration: workspaceMotion(context),
        builder: (_, value, _) => LinearProgressIndicator(
          key: const ValueKey('entry-stage-progress'),
          value: value,
          color: confirmed
              ? (dark ? const Color(0xFFB7DFC2) : const Color(0xFF3E6B54))
              : (dark ? WorkspaceTheme.peach : WorkspaceTheme.charcoal),
          backgroundColor: dark
              ? const Color(0xFF565959)
              : WorkspaceTheme.border,
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _cover(BuildContext context, bool compact, {bool phone = false}) {
    final detail = [
      company,
      if (job?['customer'] != null || job?['customer_name'] != null)
        knittingCustomerTitle(job!),
      if (job?['name'] != null) knittingJobTitle(job!),
    ].join('  ·  ');
    final stage = confirmed
        ? 2
        : review
        ? 1
        : 0;
    if (phone) {
      final step = ['Entry', 'Review', 'Posted'][stage];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '$detail · ${action.group}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  '$step · ${stage + 1} of 3',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(child: _stageProgress(context, stage)),
          if (action.id == 'revise_rate')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Existing programme and earlier delivery prices stay unchanged.',
              ),
            ),
        ],
      );
    }
    return Panel(
      dark: true,
      radius: 16,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            headingLevel: 1,
            child: Display(action.title, size: compact ? 28 : 36, light: true),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: const TextStyle(color: WorkspaceTheme.light, height: 1.45),
          ),
          if (action.id == 'revise_rate') ...[
            const SizedBox(height: 10),
            const Text(
              'Existing programme and earlier delivery prices stay unchanged.',
              style: TextStyle(color: WorkspaceTheme.light, height: 1.4),
            ),
          ],
          const SizedBox(height: 22),
          Semantics(
            liveRegion: true,
            label: [
              'Entry, step 1 of 3',
              'Review, step 2 of 3',
              'Posted, step 3 of 3',
            ][stage],
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final (i, label) in [
                        'Entry',
                        'Review',
                        'Posted',
                      ].indexed)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                [
                                  Icons.edit_outlined,
                                  Icons.fact_check_outlined,
                                  Icons.check_circle_outline,
                                ][i],
                                size: 15,
                                color: i <= stage
                                    ? WorkspaceTheme.palePeach
                                    : const Color(0xFFBFBEBA),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == stage
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: i <= stage
                                        ? Colors.white
                                        : const Color(0xFFBFBEBA),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _stageProgress(context, stage, dark: true),
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
    padding: const EdgeInsets.only(top: 4, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(headingLevel: 2, child: Display(title, size: 24)),
        const SizedBox(height: 12),
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
        originalProductionOperatorField,
        configuredProductionMachineField,
        originalProductionMachineField,
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
          kind: 'StockKgItem',
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
            kind: 'ServiceItem',
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
