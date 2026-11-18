import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Publishes the Apple display preference to every route in this app.
class ReduceTransparencyScope extends StatelessWidget {
  const ReduceTransparencyScope({super.key, required this.child});

  final Widget child;

  static final _changes = const EventChannel(
    'org.localerp.workspace/reduceTransparency',
  ).receiveBroadcastStream().cast<bool>().distinct();

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Preference>()?.enabled ??
      false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return child;
    }
    return StreamBuilder<bool>(
      stream: _changes,
      initialData: true,
      builder: (context, snapshot) =>
          _Preference(enabled: snapshot.data ?? true, child: child),
    );
  }
}

class _Preference extends InheritedWidget {
  const _Preference({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_Preference oldWidget) =>
      enabled != oldWidget.enabled;
}
