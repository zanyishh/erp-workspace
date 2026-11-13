import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'knitting_models.dart';
import 'erp_api.dart';
import 'ui/workspace_ui.dart';
import 'dart:math' as math;
import 'widgets.dart';
import 'workspace_context.dart';

part 'mill_production.dart';

Future<void> _showMillSources(
  BuildContext context,
  ErpApi api,
  WidgetBuilder builder,
) async {
  if (!api.accessReady) return;
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(context: context, builder: builder);
  void dismiss() {
    if (route.isActive) navigator.removeRoute(route);
  }

  api.addAccessListener(dismiss);
  try {
    await navigator.push(route);
  } finally {
    api.removeAccessListener(dismiss);
  }
}

String _kg(Object? raw) {
  if (raw == null) return '—';
  final text = raw.toString();
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

BigInt? _milli(Object? value) {
  if (value == null) return null;
  try {
    return Kg.parse(value.toString()).milli;
  } on FormatException {
    return null;
  }
}

String _quantity(BigInt milli) {
  final scale = BigInt.from(1000);
  final whole = milli ~/ scale;
  final fraction = (milli % scale)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final integer = NumberFormat.decimalPattern('en_US').format(whole.toInt());
  return fraction.isEmpty ? integer : '$integer.$fraction';
}

class MillOverview extends StatelessWidget {
  const MillOverview({
    super.key,
    required this.api,
    required this.snapshot,
    required this.workspace,
    required this.onDestination,
    required this.onJob,
  });

  final ErpApi api;
  final KnittingSnapshot snapshot;
  final WorkspaceContext workspace;
  final void Function(String, {String? filter}) onDestination;
  final ValueChanged<Map<String, dynamic>> onJob;

  @override
  Widget build(BuildContext context) {
    final jobs = snapshot.rows('jobs');
    final rolls = snapshot.rows('rolls');
    final hasJobs = snapshot.data['jobs'] is List;
    final running = jobs.where((j) => j['status'] == 'Running').length;
    String balance(String field) {
      var sum = BigInt.zero;
      if (!hasJobs) return '—';
      for (final job in jobs) {
        final quantity = _milli((job['balances'] as Map?)?[field]);
        if (quantity == null) return '—';
        sum += quantity;
      }
      return _quantity(sum);
    }

    void showBalances(String field, String title) {
      _showMillSources(
        context,
        api,
        (dialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Balances for ${jobs.length} recent jobs', style: _meta),
                if (jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No source jobs in this snapshot.'),
                  ),
                for (final job in jobs)
                  ListTile(
                    title: Text(job['name'].toString()),
                    subtitle: Text(
                      job['customer']?.toString() ?? 'Customer unavailable',
                    ),
                    trailing: Text(
                      '${_kg((job['balances'] as Map?)?[field])} kg',
                    ),
                    onTap: () {
                      Navigator.pop(dialog);
                      onJob(job);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    final cards = [
      _JobSummary(
        running: hasJobs ? running : null,
        count: hasJobs ? jobs.length : null,
        onTap: () => onDestination('Jobs', filter: 'Running'),
      ),
      if (workspace.allows('materials'))
        _BalanceCard(
          title: 'Job yarn in store',
          amount: balance('yarn_kg'),
          detail: 'Allocated to recent jobs',
          icon: Icons.all_inbox_outlined,
          tint: const Color(0xFFDCE9D8),
          onTap: () => showBalances('yarn_kg', 'Job yarn in store'),
        ),
      if (workspace.allows('billing'))
        _BalanceCard(
          title: 'Awaiting invoice',
          amount: balance('unbilled_kg'),
          detail: 'Delivered and unbilled',
          icon: Icons.receipt_long_outlined,
          tint: const Color(0xFFF2D9C6),
          onTap: () => showBalances('unbilled_kg', 'Awaiting invoice'),
        ),
    ];
    final queues = <(String, String, String, IconData, Color, int?)>[
      if (workspace.allows('quality')) ...[
        (
          'Awaiting inspection',
          'Quality',
          'Awaiting QC',
          Icons.fact_check_outlined,
          const Color(0xFFF1D6BF),
          snapshot.data['rolls'] is List
              ? rolls.where((r) => r['state'] == 'Awaiting QC').length
              : null,
        ),
        (
          'On hold',
          'Quality',
          'On Hold',
          Icons.pause_circle_outline,
          const Color(0xFFEFDEB8),
          snapshot.data['rolls'] is List
              ? rolls.where((r) => r['state'] == 'On Hold').length
              : null,
        ),
      ],
      if (workspace.allows('delivery'))
        (
          'Ready to dispatch',
          'Delivery',
          'Released',
          Icons.local_shipping_outlined,
          const Color(0xFFD3E6CD),
          snapshot.data['rolls'] is List
              ? rolls.where((r) => r['state'] == 'Released').length
              : null,
        ),
      if (workspace.allows('planning'))
        (
          'Planned runs',
          'Planning',
          'Planned',
          Icons.event_available_outlined,
          const Color(0xFFCFDEE2),
          snapshot.data['plans'] is List
              ? snapshot
                    .rows('plans')
                    .where((r) => r['state'] == 'Planned')
                    .length
              : null,
        ),
    ];
    final queue = Panel(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Display('Work queues', size: 27),
          const SizedBox(height: 5),
          const Text('From recent rolls and plans', style: _meta),
          const SizedBox(height: 12),
          for (final (index, q) in queues.indexed) ...[
            if (index != 0) const Divider(height: 1),
            InkWell(
              onTap: () => onDestination(q.$2, filter: q.$3),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: q.$5,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(q.$4, size: 17),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        q.$1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      q.$6?.toString() ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: WorkspaceTheme.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final chart = _MillProductionChart(snapshot: snapshot, api: api);
    final showChart = workspace.allows('production');
    return ListView(
      key: PageStorageKey('mill-${snapshot.company}'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LayoutBuilder(
          builder: (_, c) {
            final gap = c.maxWidth < 600 ? 8.0 : 12.0;
            final stacked = c.maxWidth < 700;
            if (!stacked) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, card) in cards.indexed) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(flex: i == 0 ? 15 : 10, child: card),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cards.first,
                if (cards.length > 1) ...[
                  SizedBox(height: gap),
                  if (c.maxWidth >= 325 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, card) in cards.skip(1).indexed) ...[
                          if (i > 0) SizedBox(width: gap),
                          Expanded(child: card),
                        ],
                      ],
                    )
                  else
                    ...cards
                        .skip(1)
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: card,
                          ),
                        ),
                ],
              ],
            );
          },
        ),
        if (showChart || queues.isNotEmpty) ...[
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (_, c) {
              if (showChart && queues.isNotEmpty && c.maxWidth >= 770) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 17, child: chart),
                    const SizedBox(width: 14),
                    Expanded(flex: 10, child: queue),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showChart) chart,
                  if (showChart && queues.isNotEmpty)
                    const SizedBox(height: 12),
                  if (queues.isNotEmpty) queue,
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 14),
        MillJobRegister(
          jobs: jobs.take(5).toList(),
          onJob: onJob,
          title: 'Recent jobs',
          caption: 'Most recently updated',
          showOutput: workspace.allows('production'),
          empty: hasJobs ? 'No recent jobs.' : 'Job records unavailable.',
          action: TextButton.icon(
            onPressed: () => onDestination('Jobs'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Job register'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Snapshot covers up to 200 recent jobs and 500 recent records per register.',
          style: _meta,
        ),
      ],
    );
  }
}

const _meta = TextStyle(fontSize: 12, color: WorkspaceTheme.muted);
const _numeric = TextStyle(
  fontWeight: FontWeight.w600,
  fontFeatures: [ui.FontFeature.tabularFigures()],
);

class _JobSummary extends StatelessWidget {
  const _JobSummary({
    required this.running,
    required this.count,
    required this.onTap,
  });
  final int? running, count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(21),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/knitting-studio.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            excludeFromSemantics: true,
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF242E28),
                  Color(0xB1253029),
                  Color(0x18222B23),
                ],
                stops: [0, .42, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 165),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x973E4941), Color(0xB8212A24)],
                    ),
                    border: Border.all(color: const Color(0x7ACFD6C9)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            color: Color(0xFFF5CCB1),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Running jobs',
                            style: TextStyle(
                              color: WorkspaceTheme.light,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        running?.toString() ?? '—',
                        style: displayStyle(42, color: WorkspaceTheme.light),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        count == null
                            ? 'Register unavailable'
                            : 'of $count recent jobs',
                        style: const TextStyle(
                          color: Color(0xFFE3E9DF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Semantics(
              label: 'Open running jobs',
              button: true,
              child: InkWell(onTap: onTap),
            ),
          ),
        ),
        const Positioned(
          top: 13,
          right: 13,
          child: IgnorePointer(
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Color(0xDFF4F4E9),
              child: Icon(
                Icons.north_east_rounded,
                size: 14,
                color: WorkspaceTheme.ink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.detail,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title, amount, detail;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Panel(
    frosted: true,
    padding: EdgeInsets.zero,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.north_east_rounded,
                    size: 14,
                    color: WorkspaceTheme.muted,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: amount,
                    style: displayStyle(38),
                    children: [
                      TextSpan(
                        text: ' kg',
                        style: displayStyle(21, color: WorkspaceTheme.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                amount == '—' ? 'Balance unavailable' : detail,
                style: _meta,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MillJobRegister extends StatelessWidget {
  const MillJobRegister({
    super.key,
    required this.jobs,
    required this.onJob,
    required this.caption,
    required this.empty,
    required this.showOutput,
    this.title = 'Recent jobs',
    this.action,
  });
  final List<Map<String, dynamic>> jobs;
  final ValueChanged<Map<String, dynamic>> onJob;
  final String title, caption, empty;
  final bool showOutput;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Panel(
    frosted: true,
    padding: EdgeInsets.zero,
    child: LayoutBuilder(
      builder: (_, c) {
        final desktop =
            c.maxWidth >= 690 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.6;
        Widget cell(String text, int flex, {TextStyle? style}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: text,
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Display(title, size: 27),
                        const SizedBox(height: 3),
                        Text(caption, style: _meta),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            if (desktop)
              Container(
                color: const Color(0x10627463),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: WorkspaceTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                  child: Row(
                    children: [
                      cell('JOB / CUSTOMER', 25),
                      cell('DUE DATE', 12),
                      cell('MATERIAL', 12),
                      cell('TARGET KG', 11),
                      if (showOutput) cell('PRODUCED KG', 13),
                      cell('STATUS', 12),
                      const SizedBox(width: 18),
                    ],
                  ),
                ),
              ),
            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(empty, style: _meta),
              ),
            for (final job in jobs) ...[
              const Divider(height: 1),
              InkWell(
                onTap: () => onJob(job),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: desktop
                      ? Row(
                          children: [
                            Expanded(flex: 25, child: _JobIdentity(job)),
                            cell(job['due_date']?.toString() ?? '—', 12),
                            cell(job['material_mode']?.toString() ?? '—', 12),
                            cell(_kg(job['target_kg']), 11, style: _numeric),
                            if (showOutput)
                              cell(
                                _kg((job['balances'] as Map?)?['produced_kg']),
                                13,
                                style: _numeric,
                              ),
                            Expanded(
                              flex: 12,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _JobState(job['status']?.toString()),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: WorkspaceTheme.muted,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: _JobIdentity(job)),
                                _JobState(job['status']?.toString()),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Target ${_kg(job['target_kg'])} kg  ·  Due ${job['due_date'] ?? '—'}',
                              style: _meta,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _JobIdentity extends StatelessWidget {
  const _JobIdentity(this.job);
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job['name'].toString(),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          job['customer']?.toString() ?? '—',
          style: _meta,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _JobState extends StatelessWidget {
  const _JobState(this.state);
  final String? state;
  @override
  Widget build(BuildContext context) {
    final active = state == 'Running';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: active ? const Color(0xFFDFEBDD) : const Color(0xFFE8ECE7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          state ?? 'Unknown',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: active ? const Color(0xFF325E42) : const Color(0xFF47534D),
          ),
        ),
      ),
    );
  }
}
