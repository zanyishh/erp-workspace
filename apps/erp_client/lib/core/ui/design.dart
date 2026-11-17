import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/erp_models.dart';

abstract final class WorkspaceTheme {
  static const canvas = Color(0xFFE8E8E5),
      surface = Color(0xFFF4F4F0),
      charcoal = Color(0xFF1C1C1C);
  static const ink = Color(0xFF222322),
      muted = Color(0xFF646563),
      border = Color(0xFFCCCDCA);
  static const peach = Color(0xFFE99A70),
      palePeach = Color(0xFFF4D7C3),
      light = Color(0xFFF8F8F3);
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: canvas,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: charcoal,
      primary: charcoal,
      secondary: peach,
      surface: surface,
      onSurface: ink,
      onPrimary: light,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: ink),
      bodySmall: TextStyle(fontSize: 11, color: muted),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 350),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      alignLabelWithHint: true,
      errorMaxLines: 3,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ink, width: 1.4),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'BarlowCondensed',
        fontWeight: FontWeight.w600,
        fontSize: 27,
        color: ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ink,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: charcoal,
      contentTextStyle: const TextStyle(color: light, fontFamily: 'Manrope'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      minVerticalPadding: 12,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: muted,
      indicatorColor: peach,
      dividerColor: border,
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFE5E5E1)),
      dataRowMinHeight: 48,
      headingTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontWeight: FontWeight.w600,
        color: ink,
        fontSize: 13,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: border,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.macOS: WorkspaceRouteTransition(),
        TargetPlatform.windows: WorkspaceRouteTransition(),
        TargetPlatform.linux: WorkspaceRouteTransition(),
        TargetPlatform.android: WorkspacePhoneTransition(
          PredictiveBackPageTransitionsBuilder(),
        ),
        TargetPlatform.iOS: WorkspacePhoneTransition(
          CupertinoPageTransitionsBuilder(),
        ),
      },
    ),
    dividerColor: border,
  );
}

TextStyle displayStyle(double size, {Color color = WorkspaceTheme.ink}) =>
    TextStyle(
      fontFamily: 'BarlowCondensed',
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.05,
      color: color,
      letterSpacing: .2,
    );
String tally(int? value) => value?.toString() ?? '—';
String money(num? amount, String currency) {
  if (amount == null) return '—';
  // Keep the currency code for currencies that share a symbol, such as CAD.
  return NumberFormat.currency(
    name: currency,
    locale: currency == 'INR' ? 'en_IN' : 'en_US',
    decimalDigits: amount % 1 == 0 ? 0 : null,
    symbol: switch (currency) {
      'INR' => '₹',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    },
  ).format(amount);
}

IconData moduleIcon(ErpModule m) => switch (m) {
  ErpModule.accounts => Icons.account_balance_wallet_outlined,
  ErpModule.selling => Icons.storefront_outlined,
  ErpModule.buying => Icons.shopping_cart_outlined,
  ErpModule.stock => Icons.inventory_2_outlined,
  ErpModule.manufacturing => Icons.factory_outlined,
  ErpModule.projects => Icons.grid_view_outlined,
  ErpModule.assets => Icons.domain_outlined,
  ErpModule.quality => Icons.verified_outlined,
};

bool workspaceUsesPhoneNavigation(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final platform = Theme.of(context).platform;
  final mobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  return size.width < 600 || (mobile && size.shortestSide < 480);
}

/// Flutter exposes Apple's Reduce Motion on the dispatcher, separately from
/// the Remove Animations flag in MediaQuery. Keep both reactive for all routes.
class WorkspaceMotionScope extends StatefulWidget {
  const WorkspaceMotionScope({super.key, required this.child});
  final Widget child;

  @override
  State<WorkspaceMotionScope> createState() => _WorkspaceMotionScopeState();
}

class _WorkspaceMotionScopeState extends State<WorkspaceMotionScope>
    with WidgetsBindingObserver {
  bool get _systemReduceMotion => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .reduceMotion;
  late bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = _systemReduceMotion;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    final enabled = _systemReduceMotion;
    if (enabled != _reduceMotion) setState(() => _reduceMotion = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || _reduceMotion,
      ),
      child: widget.child,
    );
  }
}

bool workspaceReduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

class WorkspacePhoneTransition extends PageTransitionsBuilder {
  const WorkspacePhoneTransition(this.platformTransition);
  final PageTransitionsBuilder platformTransition;

  @override
  Duration get transitionDuration => platformTransition.transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = workspaceReduceMotion(context);
    // Keep the platform's back gesture recognizer attached in both modes.
    return platformTransition.buildTransitions(
      route,
      context,
      reduced ? kAlwaysCompleteAnimation : animation,
      reduced ? kAlwaysDismissedAnimation : secondaryAnimation,
      child,
    );
  }
}

class WorkspaceRouteTransition extends PageTransitionsBuilder {
  const WorkspaceRouteTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (workspaceReduceMotion(context)) return child;
    final opacity = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(opacity: opacity, child: child);
  }
}
