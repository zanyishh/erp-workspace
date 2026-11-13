import 'package:flutter/material.dart';

import 'design.dart';
import 'erp_models.dart';
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
    this.jobDetail = false,
    this.backLabel,
    this.onBack,
    this.onDrawerChanged,
    this.onCompany,
    this.onRecords,
    this.onGeneral,
    this.onBusinessModule,
    this.onAccount,
  });

  final WorkspaceContext workspace;
  final String page;
  final String? backLabel;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onDrawerChanged;
  final bool jobDetail;
  final ValueChanged<String> onDestination;
  final VoidCallback? onCompany, onRecords, onAccount, onGeneral;
  final ValueChanged<ErpModule>? onBusinessModule;
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
                      child: Display('Knitting', size: 25, light: true),
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
                    if (onRecords != null)
                      const Divider(color: Color(0xFF50504D), height: 24),
                    if (onRecords != null)
                      entry(
                        'Business records',
                        Icons.library_books_outlined,
                        onRecords!,
                      ),
                  ],
                ),
              ),
              if (onGeneral != null) ...[
                const Divider(color: Color(0xFF50504D), height: 12),
                Row(
                  children: [
                    Expanded(
                      child: entry(
                        'General ERP',
                        Icons.apps_rounded,
                        onGeneral!,
                      ),
                    ),
                    if (onBusinessModule != null &&
                        ErpModule.values.any(
                          (m) => workspace.readableRecords.contains(m.doctype),
                        ))
                      PopupMenuButton<ErpModule>(
                        tooltip: 'Open a business area',
                        icon: const Icon(
                          Icons.expand_more,
                          color: WorkspaceTheme.light,
                        ),
                        onSelected: (m) => choose(() => onBusinessModule!(m)),
                        itemBuilder: (_) => [
                          for (final m in ErpModule.values.where(
                            (m) =>
                                workspace.readableRecords.contains(m.doctype),
                          ))
                            PopupMenuItem(
                              value: m,
                              child: Row(
                                children: [
                                  Icon(moduleIcon(m), size: 20),
                                  const SizedBox(width: 12),
                                  Text(switch (m) {
                                    ErpModule.selling => 'Sales',
                                    ErpModule.buying => 'Purchasing',
                                    _ => m.label,
                                  }),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 1140 &&
        MediaQuery.textScalerOf(context).scale(14) < 19;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 22 : 14,
        wide ? 16 : 6,
        wide ? 22 : 14,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      tooltip: backLabel,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: Icon(
                        _destinations[page]!.$1,
                        size: 23,
                        color: WorkspaceTheme.ink,
                      ),
                    ),
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Display(
                        jobDetail ? 'Job details' : _destinations[page]!.$2,
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
          Expanded(
            child: _MillPageTransition(
              location: (page, jobDetail),
              child: child,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: Text(
                workspace.company ?? 'Knitting ERP',
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (onAccount != null)
                  IconButton(
                    tooltip: 'Account',
                    onPressed: onAccount,
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
              ],
            ),
      onDrawerChanged: onDrawerChanged,
      drawer: wide
          ? null
          : Drawer(
              child: Builder(builder: (c) => _navigation(c, drawer: true)),
            ),
      body: WorkspaceBackdrop(
        child: wide
            ? Row(
                children: [
                  SizedBox(width: 202, child: _navigation(context)),
                  Expanded(child: SafeArea(child: content)),
                ],
              )
            : SafeArea(child: content),
      ),
    );
  }
}

/// Animate only the incoming destination. Outgoing fields are immediately
/// removed from focus, semantics and hit testing, including on access changes.
class _MillPageTransition extends StatefulWidget {
  const _MillPageTransition({required this.location, required this.child});
  final (String, bool) location;
  final Widget child;
  @override
  State<_MillPageTransition> createState() => _MillPageTransitionState();
}

class _MillPageTransitionState extends State<_MillPageTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  @override
  void didUpdateWidget(covariant _MillPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.duration = workspaceMotion(context);
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    key: const ValueKey('mill-destination-transition'),
    opacity: Tween<double>(begin: .58, end: 1).animate(_curve),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(.018, 0),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}
