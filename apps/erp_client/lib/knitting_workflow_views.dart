part of 'knitting_screen.dart';

bool _hasOriginalProgramme(Map<String, dynamic> job) =>
    job['is_imported'] == true ||
    job['source_record']?.toString().isNotEmpty == true ||
    (job['programme'] as List? ?? []).whereType<Map>().any(
      (line) => line.keys.any((key) => key.toString().startsWith('source_')),
    );

const _subcontractActions = {
  'create_subcontract',
  'subcontract_issue',
  'subcontract_receive',
  'subcontract_return',
  'subcontract_bill',
  'close_subcontract',
  'reopen_subcontract',
  'short_close_subcontract',
};

const _visibleWorkflowActions = {
  ..._subcontractActions,
  'receive_yarn',
  'return_yarn',
  'allocate_yarn',
  'transfer_yarn',
  'move_yarn',
  'repack_yarn',
  'create_yarn_order',
  'bill_yarn',
  'plan',
  'produce',
  'produce_batch',
  'produce_bulk',
  'split_roll',
  'quality',
  'review_batch',
  'deliver',
  'deliver_batch',
  'return_batch',
  'invoice',
  'create_estimate',
  'create_rate',
  'set_lot_charge',
  'revise_rate',
  'create_component',
  'issue_consumable',
  'return_consumable',
  'stoppage',
};

extension _CommercialWorkflow on _KnittingScreenState {
  Future<void> _openEstimate(Map<String, dynamic> row) async {
    final company = workspace.company;
    final access = widget.api.accessRevision;
    final originPage = page;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EstimateDetail(
        api: widget.api,
        workspace: workspace,
        row: row,
        scope: _workflowScope,
      ),
    );
    if (!mounted ||
        result == null ||
        workspace.company != company ||
        access != widget.api.accessRevision ||
        !widget.api.accessReady ||
        page != originPage ||
        !workspace.destinations.contains('Estimation')) {
      return;
    }
    final current = Map<String, dynamic>.from(result['row'] as Map);
    if (result['action'] == 'open_job') {
      if (workspace.allows('jobs')) openJob({'name': current['job']});
      return;
    }
    final spec = knitActions
        .where((a) => a.id == result['action'] && a.availableIn(workspace))
        .firstOrNull;
    if (spec != null) {
      await action(
        spec,
        initial: {'quotation': current['name']},
        initialReferences: {'quotation': current},
      );
    }
  }

  Future<void> _openSubcontract(Map<String, dynamic> row) async {
    final company = workspace.company!;
    final access = widget.api.accessRevision;
    final originPage = page;
    bool current() =>
        mounted &&
        workspace.company == company &&
        access == widget.api.accessRevision &&
        widget.api.accessReady &&
        page == originPage;
    try {
      // Commands retain the existing job-version guard, even from a company register.
      final source = await widget.api.knittingSnapshot(
        company,
        job: row['job'] as String,
      );
      if (!mounted || !current()) return;
      final job = source
          .rows('jobs')
          .where((j) => j['name'] == row['job'])
          .firstOrNull;
      if (source.company != company || job == null) {
        throw const ErpException(
          'This job is no longer available. Refresh the register.',
        );
      }
      final response = await widget.api.knittingLookup(
        company,
        row['status'] == 'Completed' ? 'CompletedSubcontract' : 'Subcontract',
        row['name'] as String,
        job: row['job'] as String,
      );
      if (!mounted || !current()) return;
      final records = (response['rows'] as List? ?? []).cast<Map>();
      final fresh = records.where((r) => r['name'] == row['name']).firstOrNull;
      if (fresh == null ||
          fresh['job'] != row['job'] ||
          fresh['status'] != row['status']) {
        throw const ErpException(
          'This subcontract changed. Refresh the register before continuing.',
        );
      }
      final selectedAction = await showDialog<String>(
        context: context,
        builder: (_) => _WorkflowDialog(
          api: widget.api,
          scope: _workflowScope,
          title: row['name'].toString(),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${row['supplier']} · ${row['status']}'),
              const SizedBox(height: 8),
              Text('Job ${row['job']} · ${row['target_kg']} kg'),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final spec in knitActions.where(
                    (a) =>
                        _subcontractActions.contains(a.id) &&
                        a.id != 'create_subcontract' &&
                        a.availableIn(workspace) &&
                        (job['status'] != 'Completed') &&
                        (row['status'] == 'Completed'
                            ? a.id == 'reopen_subcontract'
                            : row['status'] == 'Open' &&
                                  a.id != 'reopen_subcontract'),
                  ))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, spec.id),
                      icon: Icon(spec.icon, size: 17),
                      label: Text(spec.title),
                    ),
                  if (row['purchase_order'] != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'purchase_order'),
                      child: const Text('Open purchase order'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      if (!current() || selectedAction == null) return;
      if (selectedAction == 'purchase_order') {
        await this.source('Purchase Order', row['purchase_order'] as String);
      } else {
        final spec = knitActions.firstWhere((a) => a.id == selectedAction);
        if (spec.availableIn(workspace)) {
          await action(
            spec,
            sourceJob: job,
            initial: {'subcontract': row['name']},
            initialReferences: {
              'subcontract': Map<String, dynamic>.from(fresh),
            },
          );
        }
      }
    } catch (e) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class _EstimateRegister extends StatefulWidget {
  const _EstimateRegister({
    required this.api,
    required this.snapshot,
    required this.workspace,
    required this.query,
    required this.searchField,
    required this.onQuery,
    required this.start,
    required this.onPage,
    required this.onOpen,
    required this.fromDate,
    required this.toDate,
    required this.onDates,
  });
  final ErpApi api;
  final KnittingSnapshot snapshot;
  final WorkspaceContext workspace;
  final String query;
  final TextEditingController searchField;
  final ValueChanged<String> onQuery;
  final int start;
  final ValueChanged<int> onPage;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final String? fromDate, toDate;
  final void Function(String?, String?) onDates;
  @override
  State<_EstimateRegister> createState() => _EstimateRegisterState();
}

class _EstimateRegisterState extends State<_EstimateRegister> {
  late final from = TextEditingController(text: widget.fromDate);
  late final to = TextEditingController(text: widget.toDate);
  String? dateError;
  @override
  void didUpdateWidget(covariant _EstimateRegister old) {
    super.didUpdateWidget(old);
    if (old.fromDate != widget.fromDate || old.toDate != widget.toDate) {
      from.text = widget.fromDate ?? '';
      to.text = widget.toDate ?? '';
      dateError = null;
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  void applyDates() {
    final lower = from.text.trim(), upper = to.text.trim();
    bool valid(String value) =>
        value.isEmpty ||
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
            DateTime.tryParse(value)?.toIso8601String().substring(0, 10) ==
                value;
    final error = !valid(lower) || !valid(upper)
        ? 'Enter valid dates as YYYY-MM-DD.'
        : lower.isNotEmpty && upper.isNotEmpty && lower.compareTo(upper) > 0
        ? 'From date must be on or before To date.'
        : null;
    setState(() => dateError = error);
    if (error == null) {
      widget.onDates(
        lower.isEmpty ? null : lower,
        upper.isEmpty ? null : upper,
      );
    }
  }

  @override
  Widget build(BuildContext context) => KnittingRegisterPage(
    api: widget.api,
    snapshot: widget.snapshot,
    collection: 'estimates',
    fromDate: widget.fromDate,
    toDate: widget.toDate,
    query: widget.query,
    start: widget.start,
    onPage: widget.onPage,
    builder: (rows, controls, loading) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in [
                    (from, 'From date · YYYY-MM-DD'),
                    (to, 'To date · YYYY-MM-DD'),
                  ])
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: entry.$1,
                        decoration: InputDecoration(labelText: entry.$2),
                        onSubmitted: (_) => applyDates(),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: applyDates,
                    child: const Text('Apply dates'),
                  ),
                  if (widget.fromDate != null || widget.toDate != null)
                    TextButton(
                      onPressed: () {
                        from.clear();
                        to.clear();
                        setState(() => dateError = null);
                        widget.onDates(null, null);
                      },
                      child: const Text('Clear dates'),
                    ),
                ],
              ),
              if (dateError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dateError!,
                    style: const TextStyle(color: Color(0xFFA23F38)),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.searchField,
                onChanged: widget.onQuery,
                decoration: const InputDecoration(
                  labelText: 'Search estimates by number or customer',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              controls,
            ],
          ),
        ),
        SliverList.list(
          children: [
            if (rows.isEmpty && !loading)
              const Panel(
                border: true,
                child: Text(
                  'No estimates match this view. Create an estimate to agree a fabric programme before opening a job.',
                ),
              ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  border: true,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => widget.onOpen(row),
                    title: Text(row['name'].toString()),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 5,
                        children: [
                          Text(row['transaction_date']?.toString() ?? '—'),
                          Text(
                            row['customer_name']?.toString() ??
                                row['party_name']?.toString() ??
                                '—',
                          ),
                          StatusChip(
                            row['converted'] == true
                                ? 'Converted'
                                : row['status']?.toString() ?? 'Estimate',
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.workspace.allows('financial_read') &&
                            row['grand_total'] != null)
                          Text(
                            '${row['currency'] ?? ''} ${row['grand_total']}',
                          ),
                        const SizedBox(width: 12),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    ),
  );
}

class _WorkflowDialog extends StatefulWidget {
  const _WorkflowDialog({
    required this.api,
    required this.title,
    required this.content,
    this.scope,
  });
  final ErpApi api;
  final String title;
  final Widget content;
  final Listenable? scope;
  @override
  State<_WorkflowDialog> createState() => _WorkflowDialogState();
}

class _WorkflowDialogState extends State<_WorkflowDialog> {
  bool invalidated = false;
  void invalidate() {
    if (mounted) setState(() => invalidated = true);
  }

  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(invalidate);
    widget.scope?.addListener(invalidate);
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(invalidate);
    widget.scope?.removeListener(invalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: invalidated
            ? const Text(
                'Access changed. Close this view and refresh the workspace.',
              )
            : widget.content,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _EstimateDetail extends StatefulWidget {
  const _EstimateDetail({
    required this.api,
    required this.workspace,
    required this.row,
    required this.scope,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final Map<String, dynamic> row;
  final Listenable scope;
  @override
  State<_EstimateDetail> createState() => _EstimateDetailState();
}

class _EstimateDetailState extends State<_EstimateDetail> {
  late Future<(Map<String, dynamic>, NativeDocument)> future = load();
  Future<(Map<String, dynamic>, NativeDocument)> load() async {
    final company = widget.workspace.company!;
    final response = await widget.api.knittingRegister(
      company,
      'estimates',
      query: widget.row['name'] as String,
    );
    if (response['company'] != company ||
        response['collection'] != 'estimates' ||
        response['rows'] is! List) {
      throw const ErpException(
        'The estimate register changed. Refresh and try again.',
      );
    }
    final row = (response['rows'] as List)
        .cast<Map>()
        .where((r) => r['name'] == widget.row['name'])
        .firstOrNull;
    if (row == null) {
      throw const ErpException('This estimate is no longer available.');
    }
    final document = await widget.api.nativeDocument(
      'Quotation',
      name: row['name'] as String,
      company: company,
    );
    if (document.data['name'] != row['name'] ||
        document.data['company'] != company ||
        document.data['modified'] != row['modified']) {
      throw const ErpException(
        'This estimate changed while opening. Close and refresh the register.',
      );
    }
    return (Map<String, dynamic>.from(row), document);
  }

  @override
  Widget build(BuildContext context) => _WorkflowDialog(
    api: widget.api,
    title: widget.row['name'].toString(),
    scope: widget.scope,
    content: FutureBuilder<(Map<String, dynamic>, NativeDocument)>(
      future: future,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) return Text(state.error.toString());
        final (row, document) = state.data!;
        final data = document.data;
        List programme = [];
        final value = data['knitting_programme'];
        if (value is List) programme = value;
        if (value is String && value.isNotEmpty) {
          try {
            final parsed = jsonDecode(value);
            if (parsed is List) programme = parsed;
          } on FormatException {
            /* Older originals remain readable below. */
          }
        }
        void choose(String id) =>
            Navigator.pop(context, {'action': id, 'row': row});
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['customer_name']?.toString() ??
                  row['party_name']?.toString() ??
                  '—',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Estimate date ${row['transaction_date'] ?? '—'}'),
            const SizedBox(height: 8),
            StatusChip(
              row['converted'] == true
                  ? 'Converted'
                  : row['status']?.toString() ?? 'Estimate',
            ),
            const SizedBox(height: 16),
            Text('Yarn owner: ${data['knitting_material_mode'] ?? '—'}'),
            const SizedBox(height: 12),
            const Text(
              'Fabric programme',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (programme.isEmpty)
              const Text('No programme details are available.'),
            for (final line in programme.whereType<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${line['fabric'] ?? 'Fabric'} · ${line['colour'] ?? '—'} · '
                  '${knittingDiameterTitle(line)} dia / ${line['gauge'] ?? '—'} G · ${line['target_kg'] ?? '—'} kg',
                ),
              ),
            if (widget.workspace.allows('financial_read') &&
                row['grand_total'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Total ${row['currency'] ?? ''} ${row['grand_total']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (row['converted'] == true &&
                    row['job'] is String &&
                    widget.workspace.allows('jobs'))
                  OutlinedButton(
                    onPressed: () => choose('open_job'),
                    child: const Text('Open converted job'),
                  ),
                for (final spec in knitActions.where(
                  (a) =>
                      a.availableIn(widget.workspace) &&
                      row['converted'] != true &&
                      (row['docstatus'] == 0
                          ? a.id == 'accept_estimate'
                          : row['docstatus'] == 1 &&
                                widget.workspace.state == 'Active' &&
                                a.id == 'job_from_estimate'),
                ))
                  FilledButton.icon(
                    onPressed: () => choose(spec.id),
                    icon: Icon(spec.icon, size: 17),
                    label: Text(spec.title),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _JobRegisterFilters extends StatefulWidget {
  const _JobRegisterFilters({
    super.key,
    required this.api,
    required this.company,
    required this.customer,
    required this.fromDate,
    required this.toDate,
    required this.onApply,
  });
  final ErpApi api;
  final String company;
  final Map<String, dynamic>? customer;
  final String? fromDate, toDate;
  final void Function(Map<String, dynamic>?, String?, String?) onApply;

  @override
  State<_JobRegisterFilters> createState() => _JobRegisterFiltersState();
}

class _JobRegisterFiltersState extends State<_JobRegisterFilters> {
  late final from = TextEditingController(text: widget.fromDate);
  late final to = TextEditingController(text: widget.toDate);
  late Map<String, dynamic>? customer = widget.customer;
  String? error;

  @override
  void didUpdateWidget(covariant _JobRegisterFilters old) {
    super.didUpdateWidget(old);
    if (old.customer != widget.customer ||
        old.fromDate != widget.fromDate ||
        old.toDate != widget.toDate) {
      customer = widget.customer;
      from.text = widget.fromDate ?? '';
      to.text = widget.toDate ?? '';
      error = null;
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  Future<void> chooseCustomer() async {
    final access = widget.api.accessRevision;
    final company = widget.company;
    final row = await pickKnitRecord(
      context,
      widget.api,
      company,
      'JobCustomer',
    );
    if (!mounted ||
        row == null ||
        widget.company != company ||
        access != widget.api.accessRevision ||
        !widget.api.accessReady) {
      return;
    }
    if (row['name'] is! String || (row['name'] as String).isEmpty) return;
    setState(() {
      customer = {
        'name': row['name'],
        'customer_name': row['customer_name'] ?? row['title'],
      };
    });
  }

  void apply() {
    final lower = from.text.trim(), upper = to.text.trim();
    bool valid(String value) =>
        value.isEmpty ||
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
            DateTime.tryParse(value)?.toIso8601String().substring(0, 10) ==
                value;
    setState(() {
      error = !valid(lower) || !valid(upper)
          ? 'Enter valid dates as YYYY-MM-DD.'
          : lower.isNotEmpty && upper.isNotEmpty && lower.compareTo(upper) > 0
          ? 'From date must be on or before To date.'
          : null;
    });
    if (error == null) {
      widget.onApply(
        customer,
        lower.isEmpty ? null : lower,
        upper.isEmpty ? null : upper,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: OutlinedButton.icon(
              key: const ValueKey('jobs-customer'),
              onPressed: chooseCustomer,
              icon: const Icon(Icons.person_outline, size: 18),
              label: Text(
                customer?['customer_name']?.toString().isNotEmpty == true
                    ? customer!['customer_name'].toString()
                    : customer == null
                    ? 'All customers'
                    : 'Selected customer',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          for (final entry in [
            (from, 'jobs-from-date', 'From job date · YYYY-MM-DD'),
            (to, 'jobs-to-date', 'To job date · YYYY-MM-DD'),
          ])
            SizedBox(
              width: 220,
              child: TextField(
                key: ValueKey(entry.$2),
                controller: entry.$1,
                decoration: InputDecoration(labelText: entry.$3),
                onSubmitted: (_) => apply(),
              ),
            ),
          OutlinedButton(onPressed: apply, child: const Text('Apply filters')),
          TextButton(
            onPressed: () {
              setState(() {
                customer = null;
                from.clear();
                to.clear();
                error = null;
              });
              widget.onApply(null, null, null);
            },
            child: const Text('Clear filters'),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Dates use the recorded job date. Jobs without that date are excluded when a date bound is applied.',
          style: TextStyle(color: WorkspaceTheme.muted),
        ),
      ),
      if (widget.customer != null ||
          widget.fromDate != null ||
          widget.toDate != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Applied: ${[if (widget.customer != null) widget.customer!['customer_name'] ?? 'Selected customer', if (widget.fromDate != null) 'From ${widget.fromDate}', if (widget.toDate != null) 'Through ${widget.toDate}'].join(' · ')}',
          ),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

List<String> get _masterCategories => knitActions
    .firstWhere((action) => action.id == 'save_master')
    .fields
    .firstWhere((field) => field.key == 'category')
    .options;

Map<String, dynamic> _masterSettings(Object? raw) {
  final parsed = raw is String
      ? (raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw))
      : raw;
  if (parsed != null && parsed is! Map) {
    throw const ErpException('The saved definition settings are unavailable.');
  }
  return Map<String, dynamic>.from(parsed as Map? ?? {});
}

extension _MasterWorkflow on _KnittingScreenState {
  Future<void> _openMaster(Map<String, dynamic> row) async {
    final company = workspace.company;
    final access = widget.api.accessRevision;
    final category = masterCategory;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MasterDetail(
        api: widget.api,
        workspace: workspace,
        row: row,
        scope: _workflowScope,
      ),
    );
    if (!mounted ||
        result == null ||
        workspace.company != company ||
        access != widget.api.accessRevision ||
        !widget.api.accessReady ||
        page != 'Factory' ||
        masterCategory != category) {
      return;
    }
    final spec = knitActions.firstWhere((action) => action.id == 'save_master');
    if (!spec.availableIn(workspace)) return;
    final settings = _masterSettings(result['specification']);
    await action(
      spec,
      initial: {
        'master': result['name'],
        'category': result['category'],
        'title': result['title'],
        'enabled': result['enabled'] == 1 || result['enabled'] == true,
        for (final key in ['description', 'value', 'severity', 'boundary_kg'])
          if (settings.containsKey(key)) key: settings[key],
      },
      initialReferences: {'master': result},
    );
  }
}

class _MasterDetail extends StatefulWidget {
  const _MasterDetail({
    required this.api,
    required this.workspace,
    required this.row,
    required this.scope,
  });
  final ErpApi api;
  final WorkspaceContext workspace;
  final Map<String, dynamic> row;
  final Listenable scope;
  @override
  State<_MasterDetail> createState() => _MasterDetailState();
}

class _MasterDetailState extends State<_MasterDetail> {
  late final future = load();
  Future<Map<String, dynamic>> load() async {
    final company = widget.workspace.company!;
    final response = await widget.api.knittingLookup(
      company,
      'Master',
      widget.row['name'] as String,
    );
    final rows = response['rows'];
    if (rows is! List || rows.any((row) => row is! Map)) {
      throw const ErpException(
        'The master lookup returned an unexpected format.',
      );
    }
    final row = rows
        .cast<Map>()
        .where((row) => row['name'] == widget.row['name'])
        .firstOrNull;
    if (row == null) {
      throw const ErpException(
        'This definition is no longer available. Refresh the register.',
      );
    }
    if (row['category'] != widget.row['category'] ||
        !_masterCategories.contains(row['category']) ||
        row['title'] is! String ||
        !const {0, 1, false, true}.contains(row['enabled']) ||
        row['modified'] is! String ||
        (row['modified'] as String).isEmpty ||
        (row['company'] != null && row['company'] != company)) {
      throw const ErpException(
        'This definition changed. Close and refresh the register.',
      );
    }
    try {
      _masterSettings(row['specification']);
    } on FormatException {
      throw const ErpException(
        'The saved definition settings are unavailable.',
      );
    }
    return Map<String, dynamic>.from(row);
  }

  @override
  Widget build(BuildContext context) => _WorkflowDialog(
    api: widget.api,
    scope: widget.scope,
    title: widget.row['title'].toString(),
    content: FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) return Text(state.error.toString());
        final row = state.data!;
        final settings = _masterSettings(row['specification']);
        const labels = {
          'description': 'Description',
          'value': 'Value',
          'severity': 'Defect severity',
          'boundary_kg': 'Service boundary kg',
          'order': 'Sort order',
          'unit': 'Unit',
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(row['category'] as String),
            Text(
              row['enabled'] == 1 || row['enabled'] == true
                  ? 'Active'
                  : 'Inactive',
            ),
            for (final setting in settings.entries)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[setting.key] ?? setting.key,
                      style: const TextStyle(color: WorkspaceTheme.muted),
                    ),
                    SelectableText(
                      setting.value is String
                          ? setting.value as String
                          : jsonEncode(setting.value),
                    ),
                  ],
                ),
              ),
            if (knitActions
                .firstWhere((action) => action.id == 'save_master')
                .availableIn(widget.workspace)) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, row),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit definition'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
