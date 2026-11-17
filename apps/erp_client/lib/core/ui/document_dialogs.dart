import 'package:flutter/material.dart';

/// Remove only the form-owned overlay, after an ongoing build finishes.
void dismissDocumentDialog(Route<dynamic>? route) {
  if (route == null || !route.isActive) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (route.isActive) route.navigator?.removeRoute(route);
  });
}
