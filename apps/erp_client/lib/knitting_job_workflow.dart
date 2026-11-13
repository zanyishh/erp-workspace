part of 'knitting_screen.dart';

enum _JobStage {
  receipt('Yarn', ArtObject.yarn),
  production('Production', ArtObject.machine),
  quality('Inspection', ArtObject.inspection),
  dispatch('Dispatch', ArtObject.dispatch),
  invoice('Invoice', ArtObject.invoice),
  completion('Completion', ArtObject.fabric);

  const _JobStage(this.label, this.art);
  final String label;
  final ArtObject art;
}

class _JobStep {
  const _JobStep(
    this.stage,
    this.title,
    this.detail, {
    this.id,
    this.initial = const {},
  });
  final _JobStage stage;
  final String title, detail;
  final String? id;
  final Map<String, dynamic> initial;
  KnitAction? get action =>
      knitActions.where((a) => a.id == id && a.needsJob).firstOrNull;
}

List<_JobStep> _jobSteps(
  Map<String, dynamic> job,
  KnittingSnapshot snapshot,
  WorkspaceContext workspace,
) {
  if (job['status'] == 'Completed') {
    return [
      const _JobStep(
        _JobStage.completion,
        'Job complete',
        'The job is closed. Its programme and posted entries are available below.',
      ),
    ];
  }
  final balances = job['balances'] as Map? ?? {};
  final workflow = job['workflow'] as Map?;
  final programme = job['programme'] as List? ?? [];
  final rolls = snapshot.rows('rolls').where((r) => r['job'] == job['name']);
  // Older snapshots still support operational actions. Only the full job
  // reconciliation can establish that every programme and physical unit is settled.
  (int, String?) cohort(String group, Set<String> states) {
    final current = workflow?[group];
    if (current is Map) {
      return ((current['count'] as num).toInt(), current['only'] as String?);
    }
    final names = rolls
        .where((r) => states.contains(r['state']))
        .map((r) => r['name']);
    return (
      names.length,
      names.length == 1 && snapshot.rows('rolls').length < 500
          ? names.single as String
          : null,
    );
  }

  final (awaiting, inspectionRoll) = cohort('inspection', {'Awaiting QC'});
  final (held, heldRoll) = cohort('held', {'On Hold', 'Rejected', 'Rework'});
  final (released, dispatchRoll) = cohort('released', {'Released'});
  BigInt kilos(Object? value) => Kg.parse(value?.toString() ?? '0').milli;
  final remaining = workflow?['remaining_lines'] as List?;
  final needsOutput =
      remaining?.isNotEmpty ??
      (kilos(job['target_kg']) >
          kilos(balances['produced_kg']) +
              kilos(balances['fabric_transfer_in_kg']));
  final yarn = kilos(balances['yarn_kg']);
  final subcontract = kilos(balances['subcontract_kg']) > BigInt.zero;
  final lot = workflow?['only_lot'];
  final line = remaining?.length == 1
      ? remaining!.single
      : programme.length == 1
      ? programme.single['id']
      : null;
  final candidates = <_JobStep>[
    if (awaiting > 0)
      _JobStep(
        _JobStage.quality,
        'Inspect the fabric',
        '$awaiting ${awaiting == 1 ? "roll is" : "rolls are"} awaiting a quality decision.',
        id: 'quality',
        initial: {'roll': ?inspectionRoll},
      ),
    if (released > 0)
      _JobStep(
        _JobStage.dispatch,
        'Dispatch released fabric',
        '$released released ${released == 1 ? "roll is" : "rolls are"} ready for a delivery challan.',
        id: 'deliver',
        initial: {
          if (dispatchRoll != null) 'rolls': [dispatchRoll],
        },
      ),
    if (kilos(balances['unbilled_kg']) > BigInt.zero &&
        workspace.allows('billing'))
      _JobStep(
        _JobStage.invoice,
        'Invoice delivered fabric',
        '${balances['unbilled_kg']} kg delivered and awaiting invoice.',
        id: 'invoice',
        initial: {
          if (workflow?['only_delivery'] != null)
            'deliveries': [workflow!['only_delivery']],
        },
      ),
    if (held > 0)
      _JobStep(
        _JobStage.quality,
        'Review the quality decision',
        '$held ${held == 1 ? "roll needs" : "rolls need"} another inspection after hold, rejection or rework.',
        id: 'quality',
        initial: {'roll': ?heldRoll},
      ),
    if (needsOutput && yarn > BigInt.zero)
      _JobStep(
        _JobStage.production,
        'Record the next production run',
        'Weigh each roll and enter the actual yarn used.',
        id: 'produce',
        initial: {
          'programme_line': ?line,
          if (lot != null)
            'inputs': [
              {'lot': lot},
            ],
        },
      ),
    if (subcontract || workflow?['open_subcontract'] == true)
      _JobStep(
        _JobStage.production,
        'Subcontract work is open',
        subcontract
            ? 'Reconcile fabric receipts and surplus yarn with the subcontractor.'
            : 'Reconcile the subcontract order, receipts and supplier bill before completion.',
      ),
    if (needsOutput && yarn == BigInt.zero && !subcontract)
      _JobStep(
        _JobStage.receipt,
        'Receive yarn for the job',
        'Book a yarn receipt against this programme, or allocate a lot already in store.',
        id: 'receive_yarn',
        initial: {
          if (job['material_mode'] != null)
            'material_owner': job['material_mode'],
          if (job['material_mode'] == 'Customer' && job['customer'] != null)
            'party': job['customer'],
        },
      ),
    if (!needsOutput && yarn > BigInt.zero)
      _JobStep(
        _JobStage.completion,
        'Settle the remaining yarn',
        '${balances['yarn_kg']} kg remains in store against this job.',
        id: 'return_yarn',
        initial: {'lot': ?lot},
      ),
    if (!needsOutput &&
        yarn == BigInt.zero &&
        workflow?['units'] != null &&
        num.tryParse('${workflow!['units']}') != 0 &&
        !subcontract)
      _JobStep(
        _JobStage.completion,
        'Reconcile the physical count',
        'Check the bags or cones still recorded against this job.',
        id: 'adjust_yarn',
        initial: const {'quantity_kg': '0'},
      ),
  ];
  if (candidates.isEmpty) {
    if (workflow != null &&
        !needsOutput &&
        ['yarn_kg', 'fabric_kg', 'subcontract_kg', 'unbilled_kg'].every(
          (key) => balances[key] != null && kilos(balances[key]) == BigInt.zero,
        ) &&
        workflow['units'] == '0' &&
        workflow['open_subcontract'] == false) {
      candidates.add(
        const _JobStep(
          _JobStage.completion,
          'Ready to complete',
          'The programme is fulfilled and the job balances are settled.',
          id: 'close_job',
        ),
      );
    } else {
      candidates.add(
        const _JobStep(
          _JobStage.completion,
          'Awaiting reconciliation',
          'The job manager can review the outstanding records and programme.',
        ),
      );
    }
  }
  // Choose available work for this role even when another department has an
  // earlier task, e.g. dispatching a released roll while another awaits QC.
  return [
    ...candidates.where(
      (s) => s.action != null && workspace.allows(s.action!.capability),
    ),
    ...candidates.where(
      (s) => s.action == null || !workspace.allows(s.action!.capability),
    ),
  ];
}

class _JobWorkflow extends StatelessWidget {
  const _JobWorkflow(this.job, this.steps, this.workspace, this.onAction);
  final Map<String, dynamic> job;
  final List<_JobStep> steps;
  final WorkspaceContext workspace;
  final Future<void> Function(KnitAction, {Map<String, dynamic> initial})
  onAction;

  @override
  Widget build(BuildContext context) {
    final step = steps.first;
    final action = step.action;
    final allowed = action != null && workspace.allows(action.capability);
    final closed = job['status'] == 'Completed';
    return Panel(
      border: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 600;
              final art = WorkspaceArt(
                step.stage.art,
                width: compact ? 94 : 190,
                height: compact ? 84 : 140,
              );
              final identity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job['name'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: WorkspaceTheme.muted,
                      letterSpacing: .7,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Display(
                    job['customer']?.toString() ?? 'Job details',
                    size: compact ? 31 : 40,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(job['status']?.toString() ?? 'Job'),
                      if (job['material_mode'] != null)
                        Text('${job['material_mode']} material'),
                      if (job['target_kg'] != null)
                        Text('${job['target_kg']} kg target'),
                      if (job['due_date'] != null)
                        Text('Due ${job['due_date']}'),
                    ],
                  ),
                ],
              );
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 10),
                  art,
                ],
              );
            },
          ),
          const Divider(height: 28),
          const Text(
            'Job progress',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: WorkspaceTheme.muted,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final stage in _JobStage.values)
                Semantics(
                  selected: step.stage == stage,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: step.stage == stage
                          ? WorkspaceTheme.palePeach
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WorkspaceArt(stage.art, width: 32, height: 29),
                          const SizedBox(width: 3),
                          Text(
                            stage.label,
                            style: TextStyle(
                              fontWeight: step.stage == stage
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          LayoutBuilder(
            builder: (_, c) {
              final description = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Display(step.title, size: 28),
                  const SizedBox(height: 5),
                  Text(
                    step.detail,
                    style: const TextStyle(color: WorkspaceTheme.muted),
                  ),
                  if (action != null && !allowed && !closed)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        'Waiting for a colleague with ${action.group.toLowerCase()} access.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              );
              final button = allowed
                  ? FilledButton.icon(
                      key: const ValueKey('next-job-action'),
                      onPressed: () => onAction(action, initial: step.initial),
                      icon: const Icon(Icons.arrow_forward, size: 17),
                      label: Text(action.title),
                    )
                  : null;
              if (c.maxWidth < 560 || button == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    description,
                    if (button != null) ...[const SizedBox(height: 12), button],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: description),
                  const SizedBox(width: 14),
                  button,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
