import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'erp_models.dart';
import 'sales_chart.dart';
import 'widgets.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.data,
    required this.onModule,
    required this.onNew,
    this.range,
    this.onRecord,
  });

  final ErpSnapshot data;
  final DateRange? range;
  final ValueChanged<ErpModule> onModule;
  final ValueChanged<ErpRecord>? onRecord;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 660;
      final wide = box.maxWidth >= 1090;
      const gap = SizedBox(height: 16);
      final chart = SalesChart(data: data, range: range);
      final inventory = _inventory();
      final orders = _orders();
      final invoices = _invoices();
      Widget split(
        Widget left,
        Widget right, {
        int leftFlex = 7,
        int rightFlex = 4,
      }) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: leftFlex, child: left),
          const SizedBox(width: 16),
          Expanded(flex: rightFlex, child: right),
        ],
      );
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 28,
          compact ? 16 : 22,
          compact ? 16 : 28,
          28,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 12,
                  spacing: 14,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.company,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: WorkspaceTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Semantics(
                          header: true,
                          child: Display(
                            'BUSINESS OVERVIEW',
                            size: compact ? 34 : 44,
                          ),
                        ),
                      ],
                    ),
                    Pill('New document', icon: Icons.add, onPressed: onNew),
                  ],
                ),
                const SizedBox(height: 19),
                if (wide) ...[
                  split(
                    Column(children: [chart, gap, invoices]),
                    Column(children: [inventory, gap, orders]),
                  ),
                ] else ...[
                  chart,
                  gap,
                  if (compact) ...[
                    orders,
                    gap,
                    inventory,
                  ] else
                    split(inventory, orders, leftFlex: 1, rightFlex: 1),
                  gap,
                  invoices,
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _inventory() {
    final items = data.count(ErpModule.stock);
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              children: [
                const Expanded(child: Display('INVENTORY', size: 28)),
                if (items != null)
                  Semantics(
                    button: true,
                    label: 'Open Stock',
                    excludeSemantics: true,
                    onTap: () => onModule(ErpModule.stock),
                    child: IconButton.outlined(
                      tooltip: 'Open Stock',
                      onPressed: () => onModule(ErpModule.stock),
                      icon: const Icon(Icons.arrow_outward, size: 17),
                    ),
                  ),
              ],
            ),
          ),
          Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(.35, .25),
                      radius: .9,
                      colors: [
                        Color(0xFFBBCBC4),
                        Color(0xFFDEE9E2),
                        Color(0x00DFE8E3),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
                    child: Image.asset(
                      'assets/images/warehouse.png',
                      fit: BoxFit.contain,
                      cacheWidth: 880,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 133, 13, 13),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Builder(
                    builder: (context) {
                      final highContrast = MediaQuery.highContrastOf(context);
                      final plate = Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: highContrast
                                ? [Colors.white, Colors.white]
                                : const [Color(0xCDFFFFFF), Color(0x9FDCEAE5)],
                          ),
                          border: Border.all(color: const Color(0xE9FFFFFF)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _inventoryValue('Catalog items', items),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: const Color(0x998C9F95),
                            ),
                            const SizedBox(width: 17),
                            Expanded(
                              child: _inventoryValue(
                                'Warehouses',
                                data.warehouses,
                              ),
                            ),
                          ],
                        ),
                      );
                      return highContrast
                          ? plate
                          : BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                              child: plate,
                            );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inventoryValue(String title, int? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value == null
            ? 'No access'
            : NumberFormat.decimalPattern().format(value),
        style: TextStyle(
          fontSize: value == null ? 17 : 27,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        title,
        style: const TextStyle(color: WorkspaceTheme.muted, fontSize: 12),
      ),
    ],
  );

  Widget _orders() => Panel(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Display('OPERATING ACTIVITY', size: 27),
        const SizedBox(height: 7),
        for (final (label, module, count) in [
          ('Sales orders', ErpModule.selling, data.count(ErpModule.selling)),
          ('Purchase orders', ErpModule.buying, data.count(ErpModule.buying)),
          (
            'Work orders',
            ErpModule.manufacturing,
            data.count(ErpModule.manufacturing),
          ),
          (
            'Unpaid invoices',
            ErpModule.accounts,
            data.invoicesAvailable ? data.unpaidInvoices : null,
          ),
        ])
          _metricRow(label, module, count),
      ],
    ),
  );

  Widget _metricRow(String label, ErpModule module, int? count) {
    final value = count == null
        ? 'No access'
        : NumberFormat.decimalPattern().format(count);
    final open = count == null ? null : () => onModule(module);
    return Semantics(
      button: open != null,
      label: open == null
          ? '$label, no access'
          : '$label, $value. Open ${module.label}',
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            constraints: const BoxConstraints(minHeight: 51),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFD8DED7), width: .8),
              ),
            ),
            child: Row(
              children: [
                Icon(moduleIcon(module), size: 17, color: WorkspaceTheme.muted),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: count == null ? 12 : 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  open == null ? Icons.lock_outline : Icons.chevron_right,
                  size: 17,
                  color: WorkspaceTheme.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _invoices() => Panel(
    padding: const EdgeInsets.fromLTRB(20, 15, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Display('RECENT INVOICES', size: 27)),
            if (data.invoicesAvailable)
              TextButton(
                onPressed: () => onModule(ErpModule.accounts),
                child: const Text('View all'),
              ),
          ],
        ),
        if (data.activity.isEmpty || !data.invoicesAvailable)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Text(
              data.invoicesAvailable
                  ? 'No invoices in this period.'
                  : 'Invoice access unavailable.',
              style: const TextStyle(color: WorkspaceTheme.muted),
            ),
          )
        else
          for (final record in data.activity.take(4)) _invoiceRow(record),
      ],
    ),
  );

  Widget _invoiceRow(ErpRecord record) {
    final amount = record.data[record.module.amountField] == null
        ? '—'
        : invoiceMoney(record.amount, record.currency ?? data.currency);
    final open = onRecord == null ? null : () => onRecord!(record);
    return Semantics(
      button: open != null,
      onTap: open,
      excludeSemantics: true,
      label: [
        record.title,
        record.name,
        record.status,
        amount,
        if (open != null) 'Open invoice',
      ].where((s) => s.isNotEmpty).join(', '),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: open,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFD8DED7), width: .8),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6EAE4),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: Color(0xFF536159),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (record.title != record.name)
                        Text(
                          record.name,
                          style: const TextStyle(
                            color: WorkspaceTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amount,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (record.status.isNotEmpty)
                        Text(
                          record.status,
                          style: const TextStyle(
                            color: WorkspaceTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (open != null) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: WorkspaceTheme.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
