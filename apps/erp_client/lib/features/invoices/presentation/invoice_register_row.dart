import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/design.dart';
import '../../../core/ui/record_identity.dart';
import '../models/invoice_number.dart';

class InvoiceRegisterRow extends StatelessWidget {
  const InvoiceRegisterRow({
    super.key,
    required this.focusNode,
    this.identity,
    required this.row,
    required this.compact,
    required this.onOpen,
    required this.onPreview,
  });
  final RecordIdentityTransition? identity;
  final FocusNode focusNode;
  final Map row;
  final bool compact;
  final VoidCallback onOpen, onPreview;
  @override
  Widget build(BuildContext context) {
    final id = row['name'].toString(),
        customer = (row['customer_name'] ?? row['customer'] ?? '').toString();
    final issued = DateTime.tryParse(row['posting_date']?.toString() ?? '');
    final date = issued == null
        ? '—'
        : DateFormat('d MMM yyyy', 'en_US').format(issued);
    final currency = (row['currency'] ?? '').toString();
    final value = row['payable_total'] ?? row['grand_total'];
    final places = int.tryParse(row['precision']?.toString() ?? '') ?? 2;
    final prefix = currency == 'INR'
        ? '₹'
        : currency.isEmpty
        ? ''
        : '$currency ';
    final total = value == null
        ? '—'
        : '$prefix${formatInvoiceNumber(value, places: places, indian: currency == 'INR')}';
    final status = row['status']?.toString() ?? '';
    final tone = switch (status) {
      'Paid' => const Color(0xff235847),
      'Overdue' => const Color(0xff9b3635),
      'Unpaid' || 'Partly Paid' => const Color(0xff845611),
      _ => WorkspaceTheme.muted,
    };
    final label = Text(
      status,
      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: tone),
    );
    final preview = row['can_print'] == true
        ? IconButton(
            tooltip: 'Preview $id',
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            onPressed: onPreview,
          )
        : const SizedBox.shrink();
    final title =
        identity?.label() ??
        Text(
          id,
          style: const TextStyle(fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
    final job = (row['knitting_job_reference'] ?? row['knitting_job'])
        ?.toString();
    final jobLabel = job == null || job.isEmpty
        ? null
        : Text(
            'Job $job',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
    if (compact) {
      return InkWell(
        focusNode: focusNode,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 5, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    Text(customer),
                    ?jobLabel,
                    Text(date, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      total,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    label,
                  ],
                ),
              ),
              SizedBox(width: 48, child: preview),
            ],
          ),
        ),
      );
    }
    return InkWell(
      focusNode: focusNode,
      onTap: onOpen,
      child: InvoiceRegisterColumns(
        identity: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(customer, style: Theme.of(context).textTheme.bodySmall),
            ?jobLabel,
          ],
        ),
        issued: Text(date),
        status: label,
        total: Text(
          total,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: Row(
          children: [
            SizedBox(width: 48, child: preview),
            SizedBox(
              width: 48,
              child: IconButton(
                tooltip: 'Open $id',
                onPressed: onOpen,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InvoiceRegisterColumns extends StatelessWidget {
  const InvoiceRegisterColumns({
    super.key,
    required this.identity,
    required this.issued,
    required this.status,
    required this.total,
    this.actions,
  });
  final Widget identity, issued, status, total;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Expanded(flex: 4, child: identity),
        Expanded(flex: 2, child: issued),
        Expanded(flex: 2, child: status),
        Expanded(flex: 2, child: total),
        const SizedBox(width: 8),
        SizedBox(width: 96, child: actions),
      ],
    ),
  );
}
