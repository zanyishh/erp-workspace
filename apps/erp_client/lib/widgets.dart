import 'package:flutter/material.dart';
import 'design.dart';

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.dark = false,
    this.padding = const EdgeInsets.all(20),
    this.border = false,
  });
  final Widget child;
  final bool dark, border;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: dark ? WorkspaceTheme.charcoal : WorkspaceTheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: border ? Border.all(color: WorkspaceTheme.border) : null,
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: dark ? WorkspaceTheme.light : WorkspaceTheme.ink),
      child: child,
    ),
  );
}

class Display extends StatelessWidget {
  const Display(this.text, {super.key, this.size = 24, this.light = false});
  final String text;
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: displayStyle(
      size,
      color: light ? WorkspaceTheme.light : WorkspaceTheme.ink,
    ),
  );
}

class CircleControl extends StatelessWidget {
  const CircleControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.light = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool light;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: light ? WorkspaceTheme.surface : WorkspaceTheme.charcoal,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 17,
            color: light ? WorkspaceTheme.ink : WorkspaceTheme.light,
          ),
        ),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.light = false,
    this.outline = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool light, outline;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: light ? WorkspaceTheme.ink : WorkspaceTheme.light,
      backgroundColor: outline
          ? Colors.transparent
          : (light ? WorkspaceTheme.surface : WorkspaceTheme.charcoal),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
      shape: StadiumBorder(
        side: outline
            ? const BorderSide(color: WorkspaceTheme.border)
            : BorderSide.none,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.footer,
    this.icon,
  });
  final String label, value, footer;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          WorkspaceTheme.surface,
          WorkspaceTheme.surface,
          WorkspaceTheme.palePeach,
        ],
        stops: [0, .50, 1],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: WorkspaceTheme.ink),
              ),
            ),
            if (icon != null) Icon(icon, size: 15, color: WorkspaceTheme.muted),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              height: 1.05,
              fontWeight: FontWeight.w600,
              color: WorkspaceTheme.ink,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          footer,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            color: WorkspaceTheme.muted,
          ),
        ),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.dark = false});
  final String label;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(
        color: dark ? const Color(0xFF51564E) : WorkspaceTheme.border,
      ),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: dark ? WorkspaceTheme.palePeach : WorkspaceTheme.muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: dark ? WorkspaceTheme.light : WorkspaceTheme.muted,
            ),
          ),
        ),
      ],
    ),
  );
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.label = 'Try again',
  });
  final String title, message, label;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Panel(
            border: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 36,
                  color: WorkspaceTheme.muted,
                ),
                const SizedBox(height: 18),
                Display(title, size: 28),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: WorkspaceTheme.muted,
                    height: 1.6,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 20),
                  Pill(label, onPressed: action),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
