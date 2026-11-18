import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_fields.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'ui/access_gate.dart';

typedef _AllocationScope = ({int revision, int generation, String account});

class PaymentReconciliationScreen extends StatefulWidget {
  const PaymentReconciliationScreen({
    super.key,
    required this.api,
    required this.company,
  });
  final ErpApi api;
  final String company;
  @override
  State<PaymentReconciliationScreen> createState() =>
      _PaymentReconciliationState();
}

class _PaymentReconciliationState extends State<PaymentReconciliationScreen> {
  String type = 'Customer', party = '';
  Map<String, dynamic>? entries, payment, invoice;
  String? error, receipt, amountError, operationId;
  bool loading = false, posting = false, uncertain = false, journaled = false;
  bool allowLeave = false;
  int request = 0;
  int scopeGeneration = 0;
  late int accessRevision;
  late bool accessReady;
  DialogRoute<bool>? reviewRoute;
  final amount = TextEditingController();
  final amountFocus = FocusNode();
  final amountKey = GlobalKey();
  final paymentFilter = TextEditingController();
  final invoiceFilter = TextEditingController();
  bool get locked => posting || uncertain;

  @override
  void initState() {
    super.initState();
    accessRevision = widget.api.accessRevision;
    accessReady = widget.api.accessReady;
    widget.api.addAccessListener(accessChanged);
  }

  void accessChanged() {
    if (!mounted ||
        accessRevision == widget.api.accessRevision &&
            accessReady == widget.api.accessReady) {
      return;
    }
    accessRevision = widget.api.accessRevision;
    accessReady = widget.api.accessReady;
    dismissReview();
    setState(() {
      scopeGeneration++;
      request++;
      entries = payment = invoice = null;
      amount.clear();
      party = '';
      paymentFilter.clear();
      invoiceFilter.clear();
      receipt = amountError = null;
      loading = false;
      if (posting || operationId != null) uncertain = true;
      posting = false;
      error = uncertain
          ? 'Access changed. Check the saved outcome before another allocation.'
          : null;
    });
  }

  void dismissReview() {
    final route = reviewRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    reviewRoute = null;
  }

  @override
  void didUpdateWidget(covariant PaymentReconciliationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api == widget.api && oldWidget.company == widget.company) {
      return;
    }
    oldWidget.api.removeAccessListener(accessChanged);
    widget.api.addAccessListener(accessChanged);
    dismissReview();
    request++;
    scopeGeneration++;
    accessRevision = widget.api.accessRevision;
    accessReady = widget.api.accessReady;
    entries = payment = invoice = null;
    error = receipt = amountError = operationId = null;
    party = '';
    amount.clear();
    paymentFilter.clear();
    invoiceFilter.clear();
    loading = posting = uncertain = journaled = allowLeave = false;
  }

  _AllocationScope get scope => (
    revision: widget.api.accessRevision,
    generation: scopeGeneration,
    account: widget.api.account,
  );

  bool current(ErpApi api, String company, _AllocationScope epoch) =>
      mounted &&
      identical(api, widget.api) &&
      company == widget.company &&
      epoch.revision == api.accessRevision &&
      epoch.generation == scopeGeneration &&
      epoch.account == api.account &&
      api.accessReady;

  @override
  void dispose() {
    widget.api.removeAccessListener(accessChanged);
    amount.dispose();
    amountFocus.dispose();
    paymentFilter.dispose();
    invoiceFilter.dispose();
    super.dispose();
  }

  Future<void> load({
    bool accessCheck = false,
    bool afterResolution = false,
  }) async {
    if (locked && !accessCheck && !afterResolution) return;
    final api = widget.api, company = widget.company;
    final epoch = scope;
    if (accessCheck) {
      final context = await api.workspaceContext(company: company);
      if (!context.canReconcilePayments) {
        throw const ErpException(
          'Payment reconciliation is unavailable for this account.',
        );
      }
    }
    if (!current(api, company, epoch)) return;
    if (locked && accessCheck) return;
    final generation = ++request;
    setState(() {
      entries = payment = invoice = null;
      amount.clear();
      amountError = null;
      error = null;
      loading = party.isNotEmpty;
      if (accessCheck) receipt = null;
    });
    if (party.isEmpty) return;
    try {
      final result = await api.reconciliationEntries(
        company,
        type,
        party,
        paymentQuery: paymentFilter.text.trim(),
        invoiceQuery: invoiceFilter.text.trim(),
      );
      if (current(api, company, epoch) && request == generation) {
        setState(() {
          entries = result;
          loading = false;
        });
      }
    } catch (e) {
      if (current(api, company, epoch) && request == generation) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
      if (accessCheck) rethrow;
    }
  }

  void select(Map<String, dynamic> row, bool isPayment) {
    if (locked) return;
    setState(() {
      if (isPayment) {
        payment = row;
      } else {
        invoice = row;
      }
      receipt = error = null;
      amountError = null;
      if (payment != null && invoice != null) {
        amount.text = math
            .min(
              double.parse(payment!['balance']),
              double.parse(invoice!['balance']),
            )
            .toString();
      }
    });
  }

  Future<void> confirm() async {
    final pay = payment, inv = invoice;
    final value = amount.text.trim();
    final quantity = double.tryParse(value);
    if (pay == null || inv == null || locked || !widget.api.accessReady) return;
    if (quantity == null ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity >
            math.min(
              double.parse(pay['balance']),
              double.parse(inv['balance']),
            )) {
      setState(
        () => amountError = 'Enter a positive amount within both balances.',
      );
      amountFocus.requestFocus();
      final field = amountKey.currentContext;
      if (field != null) await Scrollable.ensureVisible(field, alignment: .5);
      return;
    }
    final api = widget.api, company = widget.company;
    final epoch = scope, reviewedRequest = request;
    final reviewedType = type, reviewedParty = party;
    final currency = entries!['currency'];
    final route = DialogRoute<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Apply payment to invoice?'),
        content: Text(
          '$party\n\nApply $currency $value from ${pay['name']} to ${inv['name']}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Apply payment'),
          ),
        ],
      ),
    );
    reviewRoute = route;
    final approved = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (identical(reviewRoute, route)) reviewRoute = null;
    if (!current(api, company, epoch) ||
        approved != true ||
        reviewedRequest != request ||
        locked) {
      return;
    }
    final useJournal = api.supportsOperationRecovery(company);
    final id = useJournal
        ? 'reconcile-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 30)}'
        : null;
    setState(() {
      posting = true;
      journaled = useJournal;
      operationId = id;
      amountError = null;
      error = receipt = null;
    });
    try {
      if (id != null) {
        final prepared = await api.beginOperation(
          company,
          'reconciliation',
          id,
        );
        if (!current(api, company, epoch) || operationId != id) return;
        if (prepared['state'] != 'prepared') {
          await resolve(prepared, api, company, epoch, id, currency.toString());
          return;
        }
      }
      final result = await api.allocatePayment(
        company,
        reviewedType,
        reviewedParty,
        payment: pay['name'],
        invoice: inv['name'],
        amount: value,
        expectedPayment: pay['balance'],
        expectedInvoice: inv['balance'],
        requestId: id,
      );
      if (!current(api, company, epoch) || operationId != id) return;
      await confirmed(result, api, company, epoch, id, currency.toString());
    } catch (e) {
      if (current(api, company, epoch) && operationId == id) {
        final rejected =
            e is ErpException && (e.validationRejected || e.permissionDenied);
        if (rejected && id != null) {
          try {
            final closed = await api.closeOperation(company, id);
            if (!current(api, company, epoch) || operationId != id) return;
            if (closed['state'] == 'completed') {
              await resolve(
                closed,
                api,
                company,
                epoch,
                id,
                currency.toString(),
              );
              return;
            }
            if (closed['state'] == 'closed') {
              setState(() {
                operationId = null;
                uncertain = false;
                error = e.toString();
              });
              acknowledgeAfterFrame(api, company, epoch, id);
              return;
            }
          } catch (_) {
            /* Retain the reference until its outcome can be checked. */
          }
        }
        setState(() {
          uncertain = !rejected || id != null;
          error = uncertain
              ? 'The allocation could not be confirmed. ${id != null ? 'Check its saved outcome before continuing.' : 'Ask a manager to verify this payment before another allocation.'} $e'
              : e.toString();
        });
      }
    } finally {
      if (current(api, company, epoch)) {
        setState(() => posting = false);
      }
    }
  }

  void acknowledgeAfterFrame(
    ErpApi api,
    String company,
    _AllocationScope epoch,
    String? id,
  ) {
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!current(api, company, epoch)) return;
      try {
        await api.acknowledgeOperation(company, id);
      } catch (_) {
        /* The confirmed receipt remains available in pending operations. */
      }
    });
  }

  Future<void> confirmed(
    Map<String, dynamic> result,
    ErpApi api,
    String company,
    _AllocationScope epoch,
    String? id,
    String currency,
  ) async {
    if (!current(api, company, epoch) || operationId != id) return;
    setState(() {
      receipt =
          '$currency ${result['allocated']} applied to ${result['invoice']}. After this allocation — Invoice outstanding: $currency ${result['invoice_balance']}. Payment remaining: $currency ${result['payment_balance']}.';
      uncertain = false;
      operationId = null;
      error = null;
    });
    acknowledgeAfterFrame(api, company, epoch, id);
    if (current(api, company, epoch)) await load(afterResolution: true);
  }

  Future<void> resolve(
    Map<String, dynamic> status,
    ErpApi api,
    String company,
    _AllocationScope epoch,
    String id,
    String currency,
  ) async {
    if (!current(api, company, epoch) || operationId != id) return;
    if (status['state'] == 'completed') {
      await confirmed(
        objectMap(status['result']),
        api,
        company,
        epoch,
        id,
        currency,
      );
    } else if (status['state'] == 'closed') {
      setState(() {
        uncertain = false;
        operationId = null;
        receipt = 'No allocation was posted. Review refreshed balances before continuing.';
        error = null;
      });
      acknowledgeAfterFrame(api, company, epoch, id);
      if (current(api, company, epoch)) await load(afterResolution: true);
    } else {
      setState(() {
        uncertain = true;
        error = 'The allocation is still unconfirmed. Keep checking, or close it before reviewing another allocation.';
      });
    }
  }

  Future<void> checkOutcome({bool close = false}) async {
    final id = operationId;
    if (posting || id == null || !widget.api.accessReady) return;
    final api = widget.api, company = widget.company, epoch = scope;
    final currency = entries?['currency']?.toString() ?? '';
    setState(() {
      posting = true;
      error = null;
    });
    try {
      final status = close
          ? await api.closeOperation(company, id)
          : await api.operationStatus(company, id);
      await resolve(status, api, company, epoch, id, currency);
    } catch (e) {
      if (current(api, company, epoch) && operationId == id) {
        setState(() => error = 'The outcome is still unconfirmed. $e');
      }
    } finally {
      if (current(api, company, epoch)) {
        setState(() => posting = false);
      }
    }
  }

  Future<void> leave() async {
    if (posting) {
      setState(
        () => error = 'Wait for the allocation check to finish before leaving.',
      );
      return;
    }
    if (!uncertain || !journaled || operationId == null) return;
    final api = widget.api, company = widget.company, epoch = scope;
    final id = operationId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Check this allocation later?'),
        content: const Text(
          'Its reference will remain in Pending operations. Check that outcome before making another allocation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep checking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave and check later'),
          ),
        ],
      ),
    );
    if (!current(api, company, epoch) ||
        approved != true ||
        posting ||
        operationId != id) {
      return;
    }
    setState(() => allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Widget selector(String label, bool isPayment) {
    final rows = (entries![isPayment ? 'payments' : 'invoices'] as List)
        .map(objectMap)
        .toList();
    final selected = isPayment ? payment : invoice;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$request'),
      isExpanded: true,
      initialValue: selected?['name'],
      decoration: InputDecoration(labelText: label),
      hint: Text(rows.isEmpty ? 'No matching entries' : 'Select an entry'),
      items: [
        for (final row in rows)
          DropdownMenuItem(
            value: row['name'] as String,
            child: Text(
              "${row['name']} · ${entries!['currency']} ${row['balance']}",
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: locked || rows.isEmpty
          ? null
          : (name) =>
                select(rows.firstWhere((r) => r['name'] == name), isPayment),
    );
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () => load(accessCheck: true),
    child: PopScope(
      canPop: !posting && (!uncertain || allowLeave),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Reconcile payments')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.company,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Customer', label: Text('Customer')),
                      ButtonSegment(value: 'Supplier', label: Text('Supplier')),
                    ],
                    selected: {type},
                    onSelectionChanged: locked
                        ? null
                        : (v) {
                            type = v.single;
                            party = '';
                            receipt = null;
                            paymentFilter.clear();
                            invoiceFilter.clear();
                            load();
                          },
                  ),
                  const SizedBox(height: 12),
                  NativeScalarField(
                    key: ValueKey(type),
                    field: NativeField.fromJson({
                      'fieldname': 'party',
                      'label': type,
                      'fieldtype': 'Link',
                      'options': type,
                    }),
                    linkType: type,
                    value: party,
                    editable: !locked,
                    onLink: (t, q, _) => widget.api.searchLinks(t, q),
                    onChanged: (v) {
                      party = v?.toString() ?? '';
                      receipt = null;
                      paymentFilter.clear();
                      invoiceFilter.clear();
                      load();
                    },
                  ),
                  if (party.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: const Text('Filter by document number'),
                      children: [
                        TextField(
                          controller: paymentFilter,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Payment number',
                          ),
                        ),
                        TextField(
                          controller: invoiceFilter,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Invoice number',
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: locked || loading ? null : () => load(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh balances'),
                      ),
                    ),
                  ],
                  if (loading) const LinearProgressIndicator(),
                  if (receipt != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(liveRegion: true, child: Text(receipt!)),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (uncertain && operationId != null) ...[
                    SelectableText('Reference: $operationId'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: posting ? null : () => checkOutcome(),
                          child: const Text('Check saved outcome'),
                        ),
                        TextButton(
                          onPressed: posting
                              ? null
                              : () => checkOutcome(close: true),
                          child: const Text('Close unfinished allocation'),
                        ),
                      ],
                    ),
                  ],
                  if (entries != null) ...[
                    Text(entries!['account'] as String),
                    const SizedBox(height: 12),
                    selector('Unallocated payment', true),
                    const SizedBox(height: 12),
                    selector('Outstanding invoice', false),
                    const SizedBox(height: 12),
                    TextField(
                      key: amountKey,
                      controller: amount,
                      focusNode: amountFocus,
                      enabled: !locked && payment != null && invoice != null,
                      onChanged: (_) {
                        if (amountError != null) {
                          setState(() => amountError = null);
                        }
                      },
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount to apply',
                        suffixText: entries!['currency'] as String,
                        errorText: amountError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: locked || payment == null || invoice == null
                          ? null
                          : confirm,
                      child: Text(
                        posting ? 'Applying payment…' : 'Review allocation',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
