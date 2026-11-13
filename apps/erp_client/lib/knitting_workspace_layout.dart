import 'package:flutter/material.dart';

import 'design.dart';
import 'knitting_models.dart';
import 'ui/workspace_ui.dart';
import 'widgets.dart';
import 'workspace_context.dart';

const _destinations = <String, (IconData, String)>{
  'Jobs': (Icons.assignment_outlined, 'Job register'),
  'Yarn': (Icons.all_inbox_outlined, 'Yarn store'),
  'Planning': (Icons.calendar_month_outlined, 'Machine planning'),
  'Production': (Icons.precision_manufacturing_outlined, 'Production'),
  'Quality': (Icons.fact_check_outlined, 'Quality control'),
  'Delivery': (Icons.local_shipping_outlined, 'Dispatch'),
  'Billing': (Icons.receipt_long_outlined, 'Billing'),
  'Factory': (Icons.factory_outlined, 'Factory'),
  'Reports': (Icons.bar_chart_outlined, 'Reports'),
  'Setup': (Icons.tune, 'Mill setup'),
};

class KnittingWorkspaceLayout extends StatelessWidget {
  const KnittingWorkspaceLayout({
    super.key,
    required this.workspace,
    required this.page,
    required this.onDestination,
    required this.actions,
    required this.child,
    this.onCompany,
    this.onRecords,
    this.onAccount,
  });

  final WorkspaceContext workspace;
  final String page;
  final ValueChanged<String> onDestination;
  final VoidCallback? onCompany, onRecords, onAccount;
  final List<Widget> actions;
  final Widget child;

  Widget _navigation(BuildContext context, {bool drawer = false}) {
    void choose(VoidCallback operation) {
      if (drawer) Navigator.pop(context);
      operation();
    }

    return ColoredBox(
      color: WorkspaceTheme.charcoal,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 0, 18),
                child: Row(
                  children: [
                    Icon(Icons.texture, color: WorkspaceTheme.peach, size: 25),
                    SizedBox(width: 9),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Display('KNITTING ERP', size: 25, light: true),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final name in workspace.destinations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Semantics(
                          selected: name == page,
                          child: AnimatedContainer(
                            duration: workspaceMotion(context),
                            decoration: BoxDecoration(
                              color: name == page
                                  ? WorkspaceTheme.palePeach
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: TextButton.icon(
                              onPressed: () =>
                                  choose(() => onDestination(name)),
                              style: TextButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                foregroundColor: name == page
                                    ? WorkspaceTheme.ink
                                    : WorkspaceTheme.light,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              icon: Icon(_destinations[name]!.$1, size: 19),
                              label: Text(name),
                            ),
                          ),
                        ),
                      ),
                    if (onRecords != null) ...[
                      const Divider(color: Color(0xFF494C46), height: 22),
                      TextButton.icon(
                        onPressed: () => choose(onRecords!),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: WorkspaceTheme.light,
                        ),
                        icon: const Icon(
                          Icons.library_books_outlined,
                          size: 18,
                        ),
                        label: const Text('Business records'),
                      ),
                    ],
                  ],
                ),
              ),
              if (onCompany != null || onAccount != null)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onCompany == null
                            ? null
                            : () => choose(onCompany!),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: WorkspaceTheme.palePeach,
                        ),
                        child: Text(
                          workspace.company ?? 'Switch company',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (onAccount != null)
                      IconButton(
                        tooltip: 'Account',
                        color: WorkspaceTheme.light,
                        onPressed: () => choose(onAccount!),
                        icon: const Icon(Icons.account_circle_outlined),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 970;
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: Text(workspace.company ?? 'Knitting ERP'),
              actions: [
                if (onAccount != null)
                  IconButton(
                    tooltip: 'Account',
                    icon: const Icon(Icons.account_circle_outlined),
                    onPressed: onAccount,
                  ),
              ],
            ),
      drawer: wide
          ? null
          : Drawer(
              child: Builder(builder: (c) => _navigation(c, drawer: true)),
            ),
      body: Row(
        children: [
          if (wide) SizedBox(width: 202, child: _navigation(context)),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(wide ? 26 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 20,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Display(
                          _destinations[page]!.$2.toUpperCase(),
                          size: wide ? 38 : 30,
                        ),
                        Wrap(spacing: 8, runSpacing: 4, children: actions),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KnittingJobOverview extends StatelessWidget {
  const KnittingJobOverview({super.key, required this.snapshot});
  final KnittingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final jobs = snapshot.rows('jobs');
    final rolls = snapshot.rows('rolls');
    final active = jobs.where((row) => row['status'] == 'Running').length;
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/knitting-studio.jpg',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topCenter,
                colors: [Color(0xB820221E), Colors.transparent],
                stops: [0, .72],
              ),
            ),
          ),
          Positioned(
            left: 22,
            bottom: 18,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Display(
                  '$active ${active == 1 ? "running job" : "running jobs"}',
                  size: 38,
                  light: true,
                ),
                const Text(
                  'In the recent job register',
                  style: TextStyle(color: WorkspaceTheme.light),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final queue = Panel(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Display('Roll queue', size: 26, light: true),
          const SizedBox(height: 10),
          for (final (state, label, colour) in [
            ('Awaiting QC', 'Awaiting inspection', WorkspaceTheme.palePeach),
            ('On Hold', 'On hold', WorkspaceTheme.peach),
            ('Released', 'Ready for dispatch', const Color(0xFFBDCCA8)),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 7, color: colour),
                  const SizedBox(width: 9),
                  Expanded(child: Text(label)),
                  Text(
                    '${rolls.where((r) => r['state'] == state).length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Recent rolls',
            style: TextStyle(fontSize: 11, color: Color(0xFFB8BDB5)),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (_, bounds) => bounds.maxWidth >= 690
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: SizedBox(height: 208, child: photo)),
                const SizedBox(width: 14),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 208),
                    child: queue,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 158, child: photo),
                const SizedBox(height: 10),
                queue,
              ],
            ),
    );
  }
}
