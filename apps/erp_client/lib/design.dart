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
      bodyMedium: TextStyle(fontSize: 13, color: ink),
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
