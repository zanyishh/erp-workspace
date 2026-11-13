import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'erp_models.dart';

abstract final class WorkspaceTheme {
  static const canvas = Color(0xFFE7E8E4),
      surface = Color(0xFFF4F4F0),
      charcoal = Color(0xFF191B19);
  static const ink = Color(0xFF20231F),
      muted = Color(0xFF686E66),
      border = Color(0xFFC7CBC3);
  static const peach = Color(0xFFE99A70),
      palePeach = Color(0xFFF4D7C3),
      light = Color(0xFFF8F8F3);
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: canvas,
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
        minimumSize: const Size(44, 46),
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
        minimumSize: const Size(44, 46),
        foregroundColor: ink,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
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
      headingRowColor: WidgetStatePropertyAll(palePeach),
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
        TargetPlatform.android: WorkspaceRouteTransition(),
        TargetPlatform.iOS: WorkspaceRouteTransition(),
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
String money(num? amount, String currency) => amount == null
    ? '—'
    : NumberFormat.currency(
        locale: currency == 'INR' ? 'en_IN' : 'en_US',
        decimalDigits: 0,
        symbol: switch (currency) {
          'INR' => '₹',
          'USD' => '\$',
          'EUR' => '€',
          'GBP' => '£',
          _ => '$currency ',
        },
      ).format(amount);
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
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: child,
    );
  }
}
