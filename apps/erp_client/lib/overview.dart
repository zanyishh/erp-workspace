import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'erp_models.dart';
import 'sales_chart.dart';
import 'widgets.dart';
import 'ui/workspace_art.dart';

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
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = box.maxWidth >= 1120 && scale < 1.5;
      final medium = box.maxWidth >= 720 && scale < 1.5;
      const gap = SizedBox(height: 12);
      final stage = _inventory();
      final chart = SalesChart(data: data, range: range);
      final operating = _orders();
      final directory = _directory();
      final invoices = _invoices();
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          medium ? 24 : 14,
          16,
          medium ? 24 : 14,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1580),
            child: column([
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                spacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.company,
                        style: const TextStyle(
                          color: WorkspaceTheme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Semantics(
                        header: true,
                        child: Display(
                          'BUSINESS OVERVIEW',
                          size: medium ? 37 : 31,
                        ),
                      ),
                    ],
                  ),
                  Pill('New document', icon: Icons.add, onPressed: onNew),
                ],
              ),
              const SizedBox(height: 14),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 24,
                      child: column([directory, gap, invoices]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 51, child: column([stage, gap, chart])),
                    const SizedBox(width: 12),
                    Expanded(flex: 25, child: operating),
                  ],
                )
              else if (medium)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 57,
                      child: column([stage, gap, chart, gap, invoices]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 39,
                      child: column([operating, gap, directory]),
                    ),
                  ],
                )
              else ...[
                stage,
                gap,
                chart,
                gap,
                operating,
                gap,
                directory,
                gap,
                invoices,
              ],
            ]),
          ),
        ),
      );
    },
  );

  Widget _inventory() {
    final items = data.count(ErpModule.stock);
    return Panel(
      border: true,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Display('INVENTORY', size: 26)),
              if (items != null)
                Semantics(
                  button: true,
                  label: 'Open Stock',
                  excludeSemantics: true,
                  onTap: () => onModule(ErpModule.stock),
                  child: IconButton.outlined(
                    tooltip: 'Open Stock',
                    onPressed: () => onModule(ErpModule.stock),
                    icon: const Icon(Icons.north_east, size: 17),
                  ),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (_, box) => WorkspaceArt(
              ArtObject.warehouse,
              width: box.maxWidth,
              height: (box.maxWidth * .37).clamp(131.0, 245.0),
            ),
          ),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(child: _metric('Catalog items', items)),
              Container(width: 1, height: 32, color: WorkspaceTheme.border),
              const SizedBox(width: 16),
              Expanded(child: _metric('Warehouses', data.warehouses)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, int? count) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        count == null
            ? 'No access'
            : NumberFormat.decimalPattern().format(count),
        style: TextStyle(
          fontSize: count == null ? 14 : 25,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: WorkspaceTheme.ink,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: WorkspaceTheme.muted),
      ),
    ],
  );

  Widget _directory() => Panel(
    dark: true,
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 3, 4, 12),
          child: Display('TRADING PARTNERS', size: 24, light: true),
        ),
        for (final (index, (title, art, count)) in [
          ('Customers', ArtObject.sales, data.customers),
          ('Suppliers', ArtObject.purchasing, data.suppliers),
        ].indexed) ...[
          if (index > 0) const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 4, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [WorkspaceTheme.light, Color(0xFFE7E7E1)],
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _metric(title, count)),
                Flexible(child: WorkspaceArt(art, width: 104, height: 65)),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _orders() => Panel(
    dark: true,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Display('OPERATING ACTIVITY', size: 24, light: true),
        ),
        for (final (index, (label, module, art, count)) in [
          (
            'Sales orders',
            ErpModule.selling,
            ArtObject.sales,
            data.count(ErpModule.selling),
          ),
          (
            'Purchase orders',
            ErpModule.buying,
            ArtObject.purchasing,
            data.count(ErpModule.buying),
          ),
          (
            'Work orders',
            ErpModule.manufacturing,
            ArtObject.machine,
            data.count(ErpModule.manufacturing),
          ),
          (
            'Unpaid invoices',
            ErpModule.accounts,
            ArtObject.invoice,
            data.invoicesAvailable ? data.unpaidInvoices : null,
          ),
        ].indexed) ...[
          if (index > 0) const SizedBox(height: 6),
          _metricRow(label, module, art, count),
        ],
      ],
    ),
  );

  Widget _metricRow(String label, ErpModule module, ArtObject art, int? count) {
    final value = count == null
        ? 'No access'
        : NumberFormat.decimalPattern().format(count);
    final open = count == null ? null : () => onModule(module);
    return Semantics(
      button: open != null,
      onTap: open,
      excludeSemantics: true,
      label: open == null
          ? '$label, no access'
          : '$label, $value. Open ${module.label}',
      child: Material(
        color: WorkspaceTheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
            child: Row(
              children: [
                Flexible(
                  flex: 4,
                  child: WorkspaceArt(art, width: 110, height: 74),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: _metric(label, count)),
                const SizedBox(width: 4),
                Icon(
                  open == null ? Icons.lock_outline : Icons.north_east,
                  size: 15,
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
    padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const WorkspaceArt(ArtObject.invoice, width: 44, height: 46),
            const SizedBox(width: 7),
            const Expanded(child: Display('RECENT INVOICES', size: 22)),
            if (data.invoicesAvailable)
              IconButton(
                tooltip: 'View all invoices',
                icon: const Icon(Icons.arrow_forward, size: 17),
                onPressed: () => onModule(ErpModule.accounts),
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
                top: BorderSide(color: WorkspaceTheme.border, width: .8),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
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
                          fontSize: 13,
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
