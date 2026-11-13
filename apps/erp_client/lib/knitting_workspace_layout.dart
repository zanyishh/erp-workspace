import 'package:flutter/material.dart';

import 'design.dart';
import 'ui/workspace_ui.dart';
import 'ui/workspace_art.dart';
import 'widgets.dart';
import 'workspace_context.dart';

const _destinations = <String, (IconData, String)>{
  'Overview': (Icons.space_dashboard_outlined, 'Mill overview'),
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
    this.jobDetail = false,
    this.onCompany,
    this.onRecords,
    this.onGeneral,
    this.onAccount,
  });

  final WorkspaceContext workspace;
  final String page;
  final bool jobDetail;
  final ValueChanged<String> onDestination;
  final VoidCallback? onCompany, onRecords, onAccount, onGeneral;
  final List<Widget> actions;
  final Widget child;

  Widget _navigation(BuildContext context, {bool drawer = false}) {
    void choose(VoidCallback operation) {
      if (drawer) Navigator.pop(context);
      operation();
    }

    Widget entry(
      String title,
      IconData icon,
      VoidCallback go, {
      bool active = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        selected: active,
        child: AnimatedContainer(
          duration: workspaceMotion(context),
          decoration: BoxDecoration(
            color: active ? WorkspaceTheme.palePeach : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: TextButton.icon(
            onPressed: () => choose(go),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              alignment: Alignment.centerLeft,
              foregroundColor: active
                  ? WorkspaceTheme.ink
                  : WorkspaceTheme.light,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: Icon(icon, size: 18),
            label: Text(title),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF333432),
            Color(0xFF262725),
            WorkspaceTheme.charcoal,
          ],
          stops: [0, .28, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 0, 24),
                child: Row(
                  children: [
                    Container(
                      width: 37,
                      height: 37,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3C5A8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.texture_rounded,
                        size: 23,
                        color: WorkspaceTheme.ink,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Flexible(
                      child: Display('Knitting ERP', size: 25, light: true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final name in workspace.destinations)
                      entry(
                        name,
                        _destinations[name]!.$1,
                        () => onDestination(name),
                        active: name == page,
                      ),
                    if (onRecords != null || onGeneral != null)
                      const Divider(color: Color(0xFF50504D), height: 24),
                    if (onRecords != null)
                      entry(
                        'Business records',
                        Icons.library_books_outlined,
                        onRecords!,
                      ),
                    if (onGeneral != null)
                      entry('General ERP', Icons.apps_rounded, onGeneral!),
                  ],
                ),
              ),
              if (onCompany != null || onAccount != null) ...[
                const Divider(color: Color(0xFF50504D), height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onCompany == null
                            ? null
                            : () => choose(onCompany!),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: WorkspaceTheme.light,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopBar(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    radius: 15,
    child: Row(
      children: [
        Builder(
          builder: (context) => IconButton(
            tooltip: 'All mill workspaces',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Display('Knitting ERP', size: 23),
        ),
        for (final destination in <String>{
          ...workspace.destinations.where(
            (s) => s == 'Overview' || s == 'Jobs',
          ),
          page,
        })
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              selected: destination == page,
              child: AnimatedContainer(
                duration: workspaceMotion(context),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: destination == page
                      ? WorkspaceTheme.charcoal
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: destination == page
                        ? WorkspaceTheme.light
                        : WorkspaceTheme.ink,
                  ),
                  onPressed: () => onDestination(destination),
                  icon: Icon(_destinations[destination]!.$1, size: 16),
                  label: Text(destination),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (onRecords != null)
          IconButton(
            tooltip: 'Business records',
            onPressed: onRecords,
            icon: const Icon(Icons.library_books_outlined, size: 18),
          ),
        if (onGeneral != null)
          TextButton.icon(
            onPressed: onGeneral,
            icon: const Icon(Icons.apps_rounded, size: 16),
            label: const Text('General ERP'),
          ),
        if (onCompany != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: TextButton.icon(
              onPressed: onCompany,
              icon: const Icon(Icons.business_outlined, size: 17),
              label: Text(
                workspace.company ?? 'Switch company',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (onAccount != null)
          IconButton(
            tooltip: 'Account',
            onPressed: onAccount,
            icon: const Icon(Icons.account_circle_outlined),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 1140 &&
        MediaQuery.textScalerOf(context).scale(14) < 19;
    final pageArt = switch (page) {
      'Yarn' => ArtObject.yarn,
      'Planning' || 'Production' || 'Factory' => ArtObject.machine,
      'Quality' => ArtObject.inspection,
      'Delivery' => ArtObject.dispatch,
      'Jobs' => ArtObject.fabric,
      _ => ArtObject.invoice,
    };
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: Text(workspace.company ?? 'Knitting ERP'),
              actions: [
                if (onAccount != null)
                  IconButton(
                    tooltip: 'Account',
                    onPressed: onAccount,
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
              ],
            ),
      drawer: Drawer(
        child: Builder(builder: (c) => _navigation(c, drawer: true)),
      ),
      body: WorkspaceBackdrop(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 24 : 14,
              wide ? 10 : 6,
              wide ? 24 : 14,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) ...[_desktopBar(context), const SizedBox(height: 16)],
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (page != 'Overview') ...[
                          WorkspaceArt(pageArt, width: 48, height: 45),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Semantics(
                            header: true,
                            child: Display(
                              jobDetail
                                  ? 'Job details'
                                  : _destinations[page]!.$2,
                              size: wide ? 37 : 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Wrap(spacing: 8, runSpacing: 4, children: actions),
                  ],
                ),
                SizedBox(height: wide ? 14 : 9),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
