import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'design.dart';

/// Identifies one visible record in the register that opened this route.
class RecordIdentityTransition extends ChangeNotifier {
  RecordIdentityTransition({
    required this.name,
    required this.tag,
    required this.isCurrent,
    required this.scopeChanges,
  });
  final String name;
  final Object tag;
  final bool Function() isCurrent;
  final Listenable scopeChanges;
  bool _cancelled = false;
  bool get active => !_cancelled && isCurrent();

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    notifyListeners();
  }

  Widget label({Key? key, bool expanded = false}) =>
      _RecordIdentityLabel(key: key, transition: this, expanded: expanded);
}

class _RecordIdentityLabel extends StatelessWidget {
  const _RecordIdentityLabel({
    super.key,
    required this.transition,
    required this.expanded,
  });
  final RecordIdentityTransition transition;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = _SerialFace(transition.name, expanded ? 1 : 0);
    if (workspaceReduceMotion(context) || !transition.active) return child;
    return Hero(
      tag: transition.tag,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (overlay, progress, direction, from, to) =>
          AnimatedBuilder(
            animation: Listenable.merge([
              progress,
              transition,
              transition.scopeChanges,
            ]),
            builder: (context, _) {
              // The overlay lives outside both pages' access gates.
              if (!transition.active || workspaceReduceMotion(context)) {
                return const SizedBox.shrink();
              }
              return ExcludeSemantics(
                key: ValueKey<Object>((transition.tag, 'flight')),
                child: ClipRect(
                  child: _SerialFace(transition.name, progress.value),
                ),
              );
            },
          ),
      child: child,
    );
  }
}

class _SerialFace extends StatelessWidget {
  const _SerialFace(this.name, this.progress);
  final String name;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(
          WorkspaceTheme.surface,
          WorkspaceTheme.palePeach,
          progress,
        ),
        border: Border.all(
          color: Color.lerp(
            WorkspaceTheme.border,
            WorkspaceTheme.peach,
            progress,
          )!,
        ),
        borderRadius: BorderRadius.circular(lerpDouble(5, 9, progress)!),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: lerpDouble(6, 11, progress)!,
          vertical: lerpDouble(2, 5, progress)!,
        ),
        child: Text(
          name,
          maxLines: progress < 1 ? 2 : null,
          overflow: progress < 1 ? TextOverflow.ellipsis : TextOverflow.clip,
          style: displayStyle(lerpDouble(17, 30, progress)!, color: ink),
        ),
      ),
    );
  }
}
