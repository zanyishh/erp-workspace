import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import 'design.dart';
import 'workspace_art.dart';

/// Compact navigation marks. Colour identifies a workspace; the silhouette
/// identifies the record or task. The adjacent text remains its accessible name.
class RecordIcon extends StatelessWidget {
  const RecordIcon(
    this.icon, {
    super.key,
    this.size = 36,
    this.tone = const Color(0xFF445963),
  });
  final IconData icon;
  final double size;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: Container(
        height: size,
        width: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highContrast
              ? Colors.white
              : Color.alphaBlend(
                  tone.withValues(alpha: .11),
                  WorkspaceTheme.surface,
                ),
          border: Border.all(
            color: highContrast ? Colors.black : tone.withValues(alpha: .22),
          ),
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Icon(
          icon,
          size: size * .58,
          color: highContrast ? Colors.black : tone,
        ),
      ),
    );
  }
}

/// Use the same physical object when a business record is listed and edited.
class RecordHeaderMark extends StatelessWidget {
  const RecordHeaderMark(
    this.doctype, {
    super.key,
    this.tone,
    this.settings = false,
  });
  final String doctype;
  final Color? tone;
  final bool settings;

  @override
  Widget build(BuildContext context) {
    final object = switch (doctype) {
      'Sales Order' ||
      'Customer' ||
      'Quotation' ||
      'POS Invoice' => ArtObject.sales,
      'Purchase Order' ||
      'Supplier' ||
      'Purchase Receipt' => ArtObject.purchasing,
      'Sales Invoice' ||
      'Purchase Invoice' ||
      'Payment Entry' ||
      'Journal Entry' => ArtObject.invoice,
      'Warehouse' ||
      'Warehouse Type' ||
      'Item' ||
      'Stock Entry' ||
      'Stock Reconciliation' => ArtObject.warehouse,
      'Delivery Note' || 'Shipment' => ArtObject.dispatch,
      'Work Order' ||
      'Workstation' ||
      'Job Card' ||
      'BOM' => ArtObject.assembly,
      _ => null,
    };
    return object == null
        ? RecordIcon(
            recordSymbol(doctype, settings: settings),
            tone: tone ?? const Color(0xFF445963),
          )
        : WorkspaceArt(object, width: 60, height: 40);
  }
}

(IconData, Color) moduleMark(String module) {
  final key = module.toLowerCase();
  final standard = ErpModule.values
      .where((m) => m.label.toLowerCase() == key)
      .firstOrNull;
  if (standard != null) {
    return (
      moduleIcon(standard),
      switch (standard) {
        ErpModule.accounts => const Color(0xFF2C6051),
        ErpModule.selling => const Color(0xFF835135),
        ErpModule.buying => const Color(0xFF555687),
        ErpModule.stock => const Color(0xFF476132),
        ErpModule.manufacturing => const Color(0xFF426479),
        ErpModule.projects => const Color(0xFF745570),
        ErpModule.assets => const Color(0xFF765F35),
        ErpModule.quality => const Color(0xFF28646B),
      },
    );
  }
  final icon = switch (key) {
    'quality management' => Icons.fact_check_outlined,
    'crm' => Icons.forum_outlined,
    'maintenance' => Icons.home_repair_service_outlined,
    'hr' || 'payroll' => Icons.badge_outlined,
    'support' => Icons.support_agent_outlined,
    'setup' || 'core' || 'custom' => Icons.tune_outlined,
    'integrations' || 'erpnext integrations' => Icons.hub_outlined,
    'website' => Icons.language_outlined,
    'regional' => Icons.public_outlined,
    'knitting' => Icons.texture_rounded,
    'automation' => Icons.bolt_outlined,
    'workflow' => Icons.alt_route_outlined,
    'communication' => Icons.forum_outlined,
    'email' => Icons.mail_outline,
    'printing' => Icons.print_outlined,
    'desk' => Icons.desktop_windows_outlined,
    'contacts' => Icons.contacts_outlined,
    'subcontracting' => Icons.handshake_outlined,
    'bulk transaction' => Icons.dynamic_feed_outlined,
    'edi' => Icons.swap_horizontal_circle_outlined,
    'telephony' => Icons.phone_outlined,
    'social' => Icons.groups_outlined,
    'utilities' => Icons.build_outlined,
    'geo' => Icons.map_outlined,
    'portal' => Icons.door_front_door_outlined,
    '' => Icons.apps_rounded,
    _ => Icons.folder_outlined,
  };
  return (icon, const Color(0xFF445963));
}

IconData recordSymbol(
  String name, {
  bool report = false,
  bool settings = false,
  bool tree = false,
}) {
  if (settings || name.endsWith(' Settings')) {
    return switch (name) {
      'Accounts Settings' => Icons.account_balance_outlined,
      'Selling Settings' => Icons.storefront_outlined,
      'Buying Settings' => Icons.shopping_bag_outlined,
      'Stock Settings' => Icons.inventory_outlined,
      'System Settings' => Icons.settings_outlined,
      'Print Settings' => Icons.print_outlined,
      'Manufacturing Settings' => Icons.factory_outlined,
      _ => Icons.tune_outlined,
    };
  }
  return switch (name) {
    'Customer' => Icons.person_outline,
    'Supplier' => Icons.storefront_outlined,
    'Contact' => Icons.contacts_outlined,
    'Address' => Icons.location_on_outlined,
    'Item' => Icons.inventory_2_outlined,
    'Warehouse' => Icons.warehouse_outlined,
    'Sales Invoice' => Icons.receipt_long_outlined,
    'Purchase Invoice' => Icons.request_quote_outlined,
    'Sales Order' => Icons.assignment_outlined,
    'Purchase Order' => Icons.shopping_cart_outlined,
    'Quotation' || 'Supplier Quotation' => Icons.format_quote_outlined,
    'Delivery Note' => Icons.local_shipping_outlined,
    'Purchase Receipt' => Icons.move_to_inbox_outlined,
    'Payment Entry' => Icons.payments_outlined,
    'Payment Request' => Icons.forward_to_inbox_outlined,
    'Payment Reconciliation' ||
    'Bank Reconciliation Tool' => Icons.compare_arrows_rounded,
    'Accounting Dimension' ||
    'Accounting Dimension Filter' => Icons.account_tree_outlined,
    'Fiscal Year' || 'Accounting Period' => Icons.date_range_outlined,
    'Budget' => Icons.pie_chart_outline,
    'GL Entry' || 'Finance Book' => Icons.library_books_outlined,
    'Trial Balance' || 'Balance Sheet' => Icons.balance_outlined,
    'Profit and Loss Statement' => Icons.insights_outlined,
    'Bank Transaction' => Icons.currency_exchange_outlined,
    'Payment Term' => Icons.timelapse_outlined,
    'Stock Ledger' => Icons.layers_outlined,
    'Lead' => Icons.person_search_outlined,
    'Asset Movement' => Icons.open_with_outlined,
    'Serial No' || 'Batch' => Icons.qr_code_rounded,
    'Item Price' || 'Price List' => Icons.sell_outlined,
    'Stock Reconciliation' => Icons.compare_outlined,
    'Journal Entry' => Icons.menu_book_outlined,
    'Bank Account' || 'Bank' => Icons.account_balance_outlined,
    'Account' || 'General Ledger' => Icons.account_balance_wallet_outlined,
    'Accounts Receivable' => Icons.south_west_rounded,
    'Accounts Payable' => Icons.north_east_rounded,
    'Cost Center' => Icons.donut_small_outlined,
    'Project' || 'Task' => Icons.view_kanban_outlined,
    'Asset' => Icons.domain_outlined,
    'Work Order' || 'Job Card' => Icons.precision_manufacturing_outlined,
    'Quality Inspection' => Icons.fact_check_outlined,
    'Stock Entry' => Icons.swap_horiz_rounded,
    'Stock Balance' => Icons.inventory_outlined,
    'Material Request' => Icons.playlist_add_outlined,
    'BOM' => Icons.account_tree_outlined,
    'Employee' => Icons.badge_outlined,
    'Company' => Icons.business_outlined,
    _ when tree => Icons.account_tree_outlined,
    _ when report => _reportSymbol(name.toLowerCase()),
    'Campaign' => Icons.campaign_outlined,
    'Opportunity' => Icons.flag_outlined,
    'Issue' => Icons.support_agent_outlined,
    'Timesheet' => Icons.timer_outlined,
    'Shipment' => Icons.local_shipping_outlined,
    'Delivery Trip' => Icons.route_outlined,
    'Packing Slip' => Icons.all_inbox_outlined,
    'Pick List' => Icons.checklist_rounded,
    'Production Plan' => Icons.event_note_outlined,
    'Workstation' => Icons.precision_manufacturing_outlined,
    'Operation' => Icons.build_outlined,
    'Routing' => Icons.alt_route_outlined,
    'Quality Review' => Icons.rate_review_outlined,
    'Currency' => Icons.currency_exchange_outlined,
    'UOM' => Icons.straighten_rounded,
    'Knitting Job' => Icons.assignment_outlined,
    'Knitting Machine' => Icons.precision_manufacturing_outlined,
    'Knitting Roll' => Icons.texture_rounded,
    'Knitting QC' => Icons.fact_check_outlined,
    _ when name.endsWith(' Item') => Icons.format_list_bulleted_rounded,
    _ when name.endsWith(' Group') || name.endsWith(' Type') =>
      Icons.category_outlined,
    _ when name.endsWith(' Schedule') => Icons.calendar_month_outlined,
    _ when name.endsWith(' Template') => Icons.dashboard_customize_outlined,
    _ => Icons.description_outlined,
  };
}

// Custom reports keep the standard report symbol unless their names identify
// a business concept. Identical report families retain the same visual cue.
IconData _reportSymbol(String name) {
  if (name.contains('ageing') || name.contains('expiry')) {
    return Icons.hourglass_bottom_rounded;
  }
  if (name.contains('reconciliation') || name.contains('comparison')) {
    return Icons.compare_arrows_rounded;
  }
  if (name.contains('trend') ||
      name.contains('analytics') ||
      name.contains('forecast')) {
    return Icons.show_chart_rounded;
  }
  if (name.contains('cash flow')) return Icons.currency_exchange_outlined;
  if (name.contains('receivable')) return Icons.south_west_rounded;
  if (name.contains('payable')) return Icons.north_east_rounded;
  if (name.contains('profit') || name.contains('margin')) {
    return Icons.insights_outlined;
  }
  if (name.contains('trial balance') || name.contains('financial statement')) {
    return Icons.balance_outlined;
  }
  if (name.contains('ledger') || name.contains('register')) {
    return Icons.menu_book_outlined;
  }
  if (name.contains('quality') || name.contains('inspection')) {
    return Icons.fact_check_outlined;
  }
  if (name.contains('warehouse') || name.contains('stock')) {
    return Icons.inventory_2_outlined;
  }
  if (name.contains('time') || name.contains('delayed')) {
    return Icons.schedule_outlined;
  }
  if (name.contains('tax') || name.contains('vat')) {
    return Icons.percent_rounded;
  }
  if (name.contains('project') || name.contains('task')) {
    return Icons.view_kanban_outlined;
  }
  return Icons.bar_chart_outlined;
}
