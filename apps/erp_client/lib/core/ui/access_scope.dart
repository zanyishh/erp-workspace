import 'package:flutter/material.dart';

import '../models/access_source.dart';

/// Lets mounted controls invalidate overlays even while their page is hidden.
class AccessScope extends InheritedWidget {
  const AccessScope({
    super.key,
    required this.api,
    required this.account,
    required this.revision,
    required this.ready,
    required super.child,
  });
  final AccessSource api;
  final String account;
  final int revision;
  final bool ready;

  static AccessScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccessScope>();

  Object get identity => (api, account, revision, ready);
  bool get isCurrent =>
      ready &&
      api.accessReady &&
      api.account == account &&
      api.accessRevision == revision;

  @override
  bool updateShouldNotify(AccessScope oldWidget) =>
      identity != oldWidget.identity;
}
