import 'package:flutter/material.dart';

import 'design.dart';
import 'ui/workspace_ui.dart';
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
    this.onCompany,
    this.onRecords,
    this.onGeneral,
    this.onAccount,
  });

  final WorkspaceContext workspace;
  final String page;
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
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFFF0BE9D), Color(0xFFF8E4CB)],
                  )
                : const LinearGradient(
                    colors: [Color(0x00F0BE9D), Color(0x00F8E4CB)],
                  ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: TextButton.icon(
            onPressed: () => choose(go),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              alignment: Alignment.centerLeft,
              foregroundColor: active
                  ? WorkspaceTheme.ink
                  : const Color(0xFFE2E8E0),
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
          colors: [Color(0xFF3B4740), Color(0xFF222C28), Color(0xFF1B201E)],
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
                      const Divider(color: Color(0xFF4E5B52), height: 24),
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
                const Divider(color: Color(0xFF4E5B52), height: 20),
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
      body: WorkspaceBackdrop(
        child: Row(
          children: [
            if (wide) SizedBox(width: 202, child: _navigation(context)),
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 26 : 14,
                    wide ? 24 : 10,
                    wide ? 26 : 14,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (wide) ...[
                                Text(
                                  'KNITTING  /  ${workspace.company?.toUpperCase() ?? 'WORKSPACE'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.4,
                                    color: WorkspaceTheme.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Display(
                                _destinations[page]!.$2,
                                size: wide ? 40 : 31,
                              ),
                            ],
                          ),
                          Wrap(spacing: 8, runSpacing: 4, children: actions),
                        ],
                      ),
                      SizedBox(height: wide ? 18 : 12),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
