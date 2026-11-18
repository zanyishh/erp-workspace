import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'design.dart';
import 'reduce_transparency.dart';

/// A stationary field of light gives translucent surfaces a common backdrop.
class WorkspaceBackdrop extends StatelessWidget {
  const WorkspaceBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF1F1EE), Color(0xFFE8E8E5), Color(0xFFDEDEDB)],
        stops: [0, .48, 1],
      ),
    ),
    child: child,
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.dark = false,
    this.padding = const EdgeInsets.all(20),
    this.border = false,
    this.frosted = false,
    this.radius = 16,
  });
  final Widget child;
  final bool dark, border, frosted;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    final highContrast = MediaQuery.highContrastOf(context);
    final solid = highContrast || ReduceTransparencyScope.of(context);
    final useBlur = frosted && !solid;
    final fill = dark
        ? [
            Color(frosted ? 0xCC302F2D : 0xFF242525),
            Color(frosted ? 0xE61C1C1B : 0xFF1A1B1A),
          ]
        : [
            Color(frosted ? 0xDAFFFFFC : 0xFFFFFFFC),
            Color(frosted ? 0xBDF2F0EB : 0xFFF4F4F1),
          ];
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        color: solid ? (dark ? WorkspaceTheme.charcoal : Colors.white) : null,
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: fill,
              ),
        border: Border.all(
          color: dark
              ? const Color(0xFF4B4C4A)
              : border
              ? const Color(0xFFC9CAC7)
              : const Color(0xEFFFFFFF),
        ),
      ),
      child: Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: dark ? WorkspaceTheme.light : WorkspaceTheme.ink,
          ),
          child: child,
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: useBlur
            ? const [
                BoxShadow(
                  color: Color(0x1F211E1A),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x10211E1A),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: useBlur
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
                child: CustomPaint(
                  foregroundPainter: _GlassEdge(radius, dark),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}

/// A stationary rim keeps floating navigation legible above light and dark content.
class _GlassEdge extends CustomPainter {
  const _GlassEdge(this.radius, this.dark);
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0x70FFFFFF), Color(0x12FFFFFF), Color(0x3824211F)]
          : const [Color(0xFFFFFFFF), Color(0x70FFFFFF), Color(0x452D2926)],
    );
    final outline = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius),
    ).deflate(.5);
    canvas.drawRRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.radius != radius;
}

/// Keeps record titles aligned with other route titles on compact screens.
class WorkspaceRouteTitle extends StatelessWidget {
  const WorkspaceRouteTitle(this.title, {super.key, required this.mark});

  final String title;
  final Widget mark;

  @override
  Widget build(BuildContext context) {
    final label = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (workspaceUsesPhoneNavigation(context)) return label;
    return Row(
      children: [
        ExcludeSemantics(child: mark),
        const SizedBox(width: 8),
        Flexible(child: label),
      ],
    );
  }
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
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
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
      minimumSize: const Size(48, 48),
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
    this.art,
    this.accented = true,
  });
  final String label, value, footer;
  final IconData? icon;
  final Widget? art;
  final bool accented;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: accented ? null : WorkspaceTheme.surface,
      border: accented ? null : Border.all(color: WorkspaceTheme.border),
      gradient: !accented
          ? null
          : const LinearGradient(
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
                style: const TextStyle(fontSize: 13, color: WorkspaceTheme.ink),
              ),
            ),
            ?art,
            if (art == null && icon != null)
              Icon(icon, size: 15, color: WorkspaceTheme.muted),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: WorkspaceTheme.ink,
            letterSpacing: -1,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          footer,
          style: const TextStyle(
            fontSize: 12,
            height: 1.2,
            color: WorkspaceTheme.muted,
          ),
        ),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.dark = false,
    this.monochrome = false,
  });
  final String label;
  final bool dark, monochrome;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (label.toLowerCase()) {
      'submitted' ||
      'completed' ||
      'paid' ||
      'saved' ||
      'released' => (Icons.check_circle_outline, const Color(0xFF2E634F)),
      'cancelled' ||
      'overdue' ||
      'rejected' ||
      'disabled' => (Icons.block_outlined, const Color(0xFF8E4137)),
      'unsaved changes' ||
      'draft' ||
      'new' => (Icons.edit_outlined, const Color(0xFF76582C)),
      'to deliver' || 'to deliver and bill' => (
        Icons.local_shipping_outlined,
        const Color(0xFF355D72),
      ),
      'unpaid' ||
      'to bill' ||
      'partly paid' => (Icons.schedule_outlined, const Color(0xFF8A542E)),
      'running' ||
      'in process' ||
      'active' => (Icons.play_circle_outline, const Color(0xFF35685F)),
      _ => (Icons.label_outline_rounded, WorkspaceTheme.muted),
    };
    final emphasized = const {
      'running',
      'in process',
      'active',
    }.contains(label.toLowerCase());
    final color = dark
        ? WorkspaceTheme.light
        : monochrome
        ? WorkspaceTheme.ink
        : tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.transparent
            : monochrome
            ? emphasized
                  ? WorkspaceTheme.palePeach
                  : WorkspaceTheme.canvas
            : tone.withValues(alpha: .07),
        border: Border.all(
          color: dark
              ? const Color(0xFF666B64)
              : monochrome
              ? WorkspaceTheme.border
              : tone.withValues(alpha: .25),
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 13, color: color)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
            child: Semantics(
              liveRegion: true,
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
    ),
  );
}
