import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/design.dart';
import '../../../core/models/erp_models.dart';
import 'sales_chart.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/ui/workspace_art.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.data,
    required this.onModule,
    required this.onNew,
    this.showCompany = true,
    this.range,
    this.onUnpaid,
    this.onInvoices,
    this.onRecord,
  });

  final ErpSnapshot data;
  final bool showCompany;
  final DateRange? range;
  final ValueChanged<ErpModule> onModule;
  final ValueChanged<ErpRecord>? onRecord;
  final VoidCallback onNew;
  final VoidCallback? onUnpaid, onInvoices;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final phone = workspaceUsesPhoneNavigation(context);
      final medium = !phone && box.maxWidth >= 720 && scale < 1.5;
      final landscape = phone && box.maxWidth >= 720 && scale < 1.5;
      final gapSize = medium ? 16.0 : 12.0;
      final gap = SizedBox(height: gapSize);
      final stage = _inventory(compact: !medium);
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
                      if (showCompany)
                        Text(
                          data.company,
                          style: const TextStyle(
                            color: WorkspaceTheme.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Semantics(
                        headingLevel: 1,
                        child: Display(
                          'BUSINESS OVERVIEW',
                          size: medium ? 43 : 33,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    children: [
                      if (onInvoices != null)
                        Pill(
                          'Invoices',
                          outline: true,
                          light: true,
                          onPressed: onInvoices,
                        ),
                      Pill('New document', onPressed: onNew),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (medium)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 13, child: column([stage, gap, chart])),
                    SizedBox(width: gapSize),
                    Expanded(
                      flex: 8,
                      child: column([operating, gap, invoices, gap, directory]),
                    ),
                  ],
                )
              else ...[
                if (landscape && data.invoicesAvailable)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 13, child: chart),
                      SizedBox(width: gapSize),
                      Expanded(flex: 8, child: stage),
                    ],
                  )
                else if (data.invoicesAvailable)
                  chart
                else
                  stage,
                if (data.invoicesAvailable && data.activity.isNotEmpty) ...[
                  gap,
                  invoices,
                ],
                if (!landscape && data.invoicesAvailable) ...[gap, stage],
                gap,
                operating,
                gap,
                directory,
                if (!data.invoicesAvailable) ...[gap, chart],
                if (!data.invoicesAvailable || data.activity.isEmpty) ...[
                  gap,
                  invoices,
                ],
              ],
            ]),
          ),
        ),
      );
    },
  );

  Widget _inventory({required bool compact}) {
    final items = data.count(ErpModule.stock);
    return Panel(
      border: true,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        12,
        compact ? 16 : 24,
        17,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Semantics(
                headingLevel: 2,
                child: const Display('INVENTORY', size: 29),
              ),
              if (items != null)
                Semantics(
                  button: true,
                  label: 'Open Stock',
                  excludeSemantics: true,
                  onTap: () => onModule(ErpModule.stock),
                  child: TextButton(
                    onPressed: () => onModule(ErpModule.stock),
                    child: const Text('Open stock'),
                  ),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (_, box) => WorkspaceArt(
              ArtObject.warehouse,
              width: box.maxWidth,
              height: compact
                  ? (box.maxWidth * .30).clamp(78.0, 118.0)
                  : (box.maxWidth * .35).clamp(140.0, 235.0),
            ),
          ),
          const Divider(height: 18),
          _metricPair('Catalog items', items, 'Warehouses', data.warehouses),
        ],
      ),
    );
  }

  Widget _metricPair(String left, int? first, String right, int? second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _metric(left, first)),
      const SizedBox(width: 12),
      Expanded(child: _metric(right, second)),
    ],
  );

  Widget _metric(String label, int? count) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, color: WorkspaceTheme.muted),
      ),
      const SizedBox(height: 2),
      Text(
        count == null
            ? 'No access'
            : NumberFormat.decimalPattern().format(count),
        style: TextStyle(
          fontSize: count == null ? 15 : 29,
          height: 1.15,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _directory() => Panel(
    border: true,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          headingLevel: 2,
          child: const Display('TRADING PARTNERS', size: 25),
        ),
        const Divider(height: 22),
        _metricPair('Customers', data.customers, 'Suppliers', data.suppliers),
      ],
    ),
  );

  Widget _orders() => Panel(
    dark: true,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          headingLevel: 2,
          child: const Display('OPERATING ACTIVITY', size: 27, light: true),
        ),
        const SizedBox(height: 13),
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
        ]) ...[
          Divider(
            height: 1,
            thickness: 1,
            color: WorkspaceTheme.light.withValues(alpha: .2),
          ),
          _metricRow(label, module, count),
        ],
      ],
    ),
  );

  Widget _metricRow(String label, ErpModule module, int? count) {
    final value = count == null
        ? 'No access'
        : NumberFormat.decimalPattern().format(count);
    final open = count == null
        ? null
        : module == ErpModule.accounts && onUnpaid != null
        ? onUnpaid
        : () => onModule(module);
    return Semantics(
      button: open != null,
      onTap: open,
      excludeSemantics: true,
      label: open == null
          ? '$label, no access'
          : '$label, $value. Open ${module.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: open,
          splashColor: WorkspaceTheme.light.withValues(alpha: .17),
          focusColor: WorkspaceTheme.light.withValues(alpha: .18),
          hoverColor: WorkspaceTheme.light.withValues(alpha: .10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: WorkspaceTheme.light,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: count == null
                              ? WorkspaceTheme.border
                              : WorkspaceTheme.light,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          fontSize: count == null ? 13 : 23,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    child: open == null
                        ? null
                        : const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: WorkspaceTheme.border,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _invoices() => Panel(
    border: true,
    padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            Semantics(
              headingLevel: 2,
              child: const Display('RECENT INVOICES', size: 25),
            ),
            if (data.invoicesAvailable && onInvoices != null)
              TextButton(
                onPressed: onInvoices,
                child: const Text('View all invoices'),
              ),
          ],
        ),
        if (data.activity.isEmpty || !data.invoicesAvailable)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
        : money(record.amount, record.currency ?? data.currency);
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
            constraints: const BoxConstraints(minHeight: 52),
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
                          fontFeatures: [FontFeature.tabularFigures()],
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
