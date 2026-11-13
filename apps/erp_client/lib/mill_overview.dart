import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'knitting_models.dart';
import 'erp_api.dart';
import 'ui/workspace_ui.dart';
import 'ui/workspace_art.dart';
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

    final stage = _JobSummary(
      running: hasJobs ? running : null,
      count: hasJobs ? jobs.length : null,
      onTap: () => onDestination('Jobs', filter: 'Running'),
    );
    final balances = <Widget>[
      if (workspace.allows('materials'))
        _BalanceCard(
          title: 'Job yarn in store',
          amount: balance('yarn_kg'),
          detail: 'Allocated to recent jobs',
          art: ArtObject.yarn,
          onTap: () => showBalances('yarn_kg', 'Job yarn in store'),
        ),
      if (workspace.allows('billing'))
        _BalanceCard(
          title: 'Awaiting invoice',
          amount: balance('unbilled_kg'),
          detail: 'Delivered and unbilled',
          art: ArtObject.invoice,
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
          const Color(0xFFF7D8BD),
          snapshot.data['rolls'] is List
              ? rolls.where((r) => r['state'] == 'Awaiting QC').length
              : null,
        ),
        (
          'On hold',
          'Quality',
          'On Hold',
          Icons.pause_circle_outline,
          const Color(0xFFF2DCA9),
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
          const Color(0xFFD2E4D5),
          snapshot.data['rolls'] is List
              ? rolls.where((r) => r['state'] == 'Released').length
              : null,
        ),
      if (workspace.allows('planning'))
        (
          'Planned runs',
          'Planning',
          'Planned',
          Icons.calendar_month_outlined,
          const Color(0xFFD0E1E9),
          snapshot.data['plans'] is List
              ? snapshot
                    .rows('plans')
                    .where((r) => r['state'] == 'Planned')
                    .length
              : null,
        ),
    ];
    final queue = Panel(
      border: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 3, 4, 0),
            child: Display('Work queues', size: 25),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: Text('From recent rolls and plans', style: _meta),
          ),
          for (final (i, q) in queues.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              minLeadingWidth: 0,
              horizontalTitleGap: 10,
              leading: DecoratedBox(
                decoration: BoxDecoration(
                  color: q.$5,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(q.$4, size: 20, color: WorkspaceTheme.ink),
                ),
              ),
              title: Text(
                q.$1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    q.$6?.toString() ?? '—',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: WorkspaceTheme.muted,
                  ),
                ],
              ),
              onTap: () => onDestination(q.$2, filter: q.$3),
            ),
          ],
        ],
      ),
    );
    final chart = _MillProductionChart(snapshot: snapshot, api: api);
    final showChart = workspace.allows('production');
    final summary = Panel(
      dark: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 3, 4, 12),
            child: Display('Material balances', size: 24, light: true),
          ),
          for (final (i, card) in balances.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            card,
          ],
        ],
      ),
    );
    final register = MillJobRegister(
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
    );
    return ListView(
      key: PageStorageKey('mill-${snapshot.company}'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            const gap = SizedBox(height: 12);
            Widget column(List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
            final hasQueue = queues.isNotEmpty;
            if (box.maxWidth >= 1040 && scale < 1.5) {
              return column([
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (balances.isNotEmpty) ...[
                      Expanded(flex: 22, child: summary),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 51,
                      child: column([
                        stage,
                        if (showChart) ...[gap, chart],
                      ]),
                    ),
                    if (hasQueue) ...[
                      const SizedBox(width: 12),
                      Expanded(flex: 25, child: queue),
                    ],
                  ],
                ),
                gap,
                register,
              ]);
            }
            if (box.maxWidth >= 700 &&
                scale < 1.5 &&
                (balances.isNotEmpty || hasQueue)) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 57,
                    child: column([
                      stage,
                      if (showChart) ...[gap, chart],
                      gap,
                      register,
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 39,
                    child: column([
                      if (balances.isNotEmpty) summary,
                      if (hasQueue) ...[if (balances.isNotEmpty) gap, queue],
                    ]),
                  ),
                ],
              );
            }
            return column([
              stage,
              if (hasQueue) ...[gap, queue],
              if (showChart) ...[gap, chart],
              if (balances.isNotEmpty) ...[gap, summary],
              gap,
              register,
            ]);
          },
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
  Widget build(BuildContext context) => Panel(
    border: true,
    padding: EdgeInsets.zero,
    child: Semantics(
      button: true,
      label: 'Open running jobs',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Display('Running jobs', size: 26)),
                    const Icon(
                      Icons.north_east,
                      size: 17,
                      color: WorkspaceTheme.muted,
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (_, box) => WorkspaceArt(
                    ArtObject.machine,
                    height: (box.maxWidth * .46).clamp(144.0, 275.0),
                    width: box.maxWidth,
                  ),
                ),
                const Divider(height: 10),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      running?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      count == null
                          ? 'Register unavailable'
                          : 'of $count recent jobs',
                      style: _meta,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.detail,
    required this.art,
    required this.onTap,
  });
  final String title, amount, detail;
  final ArtObject art;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: WorkspaceTheme.surface,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WorkspaceTheme.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.north_east,
                  size: 14,
                  color: WorkspaceTheme.muted,
                ),
              ],
            ),
            WorkspaceArt(art, width: double.infinity, height: 79),
            Text.rich(
              TextSpan(
                text: amount,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.7,
                  height: 1.15,
                  color: WorkspaceTheme.ink,
                ),
                children: const [
                  TextSpan(
                    text: ' kg',
                    style: TextStyle(
                      fontSize: 16,
                      letterSpacing: 0,
                      color: WorkspaceTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(amount == '—' ? 'Balance unavailable' : detail, style: _meta),
          ],
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
    this.sliverWidth,
  });
  final List<Map<String, dynamic>> jobs;
  final ValueChanged<Map<String, dynamic>> onJob;
  final String title, caption, empty;
  final bool showOutput;
  final double? sliverWidth;
  final Widget? action;

  bool _wide(BuildContext context, double width) =>
      width >= 820 && MediaQuery.textScalerOf(context).scale(12) < 18;
  @override
  Widget build(BuildContext context) {
    final width = sliverWidth;
    if (width != null) {
      final wide = _wide(context, width);
      return DecoratedSliver(
        decoration: BoxDecoration(
          color: WorkspaceTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WorkspaceTheme.border),
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: _header(wide)),
            SliverList.builder(
              itemCount: jobs.length,
              itemBuilder: (context, i) => _row(jobs[i], wide),
            ),
          ],
        ),
      );
    }
    return Panel(
      border: true,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = _wide(context, c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_header(wide), for (final job in jobs) _row(job, wide)],
          );
        },
      ),
    );
  }

  Widget _header(bool desktop) {
    Widget heading(String title, int flex, {IconData? icon}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Tooltip(
          message: title,
          child: ColumnCaption(title, icon: icon),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
          child: Row(
            children: [
              const WorkspaceArt(ArtObject.fabric, width: 48, height: 45),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Display(title, size: 24),
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
            color: const Color(0x0D292A2A),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: WorkspaceTheme.muted,
                fontWeight: FontWeight.w600,
              ),
              child: Row(
                children: [
                  heading('JOB / CUSTOMER', 25),
                  heading('DUE DATE', 12),
                  heading('MATERIAL', 12, icon: Icons.layers_outlined),
                  heading('TARGET KG', 11, icon: Icons.flag_outlined),
                  if (showOutput)
                    heading('PRODUCED KG', 13, icon: Icons.scale_outlined),
                  heading('STATUS', 12),
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
      ],
    );
  }

  Widget _row(Map<String, dynamic> job, bool desktop) {
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(width: .75, color: WorkspaceTheme.border),
        ),
      ),
      child: InkWell(
        onTap: () => onJob(job),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
    );
  }
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
