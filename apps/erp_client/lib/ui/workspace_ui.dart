import 'package:flutter/material.dart';
import '../design.dart';
import '../widgets.dart';

Duration workspaceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });
  final String title, subtitle;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Display(title.toUpperCase(), size: 38),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: WorkspaceTheme.muted),
                      ),
                    ],
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

class WorkspaceSelection extends StatelessWidget {
  const WorkspaceSelection({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              selected: selected == label,
              child: AnimatedContainer(
                duration: workspaceMotion(context),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected == label
                      ? WorkspaceTheme.charcoal
                      : WorkspaceTheme.surface,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextButton(
                  onPressed: () => onSelected(label),
                  style: TextButton.styleFrom(
                    foregroundColor: selected == label
                        ? WorkspaceTheme.light
                        : WorkspaceTheme.ink,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class WorkspaceSteps extends StatelessWidget {
  const WorkspaceSteps({super.key, required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 10,
    children: [
      for (final (i, label) in [
        'Programme',
        'Yarn',
        'Production',
        'Quality',
        'Delivery',
        'Invoice',
      ].indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: i <= current
                  ? WorkspaceTheme.charcoal
                  : WorkspaceTheme.border,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  color: WorkspaceTheme.light,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: i <= current ? WorkspaceTheme.ink : WorkspaceTheme.muted,
              ),
            ),
            if (i < 5)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: WorkspaceTheme.muted,
                ),
              ),
          ],
        ),
    ],
  );
}
