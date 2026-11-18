import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_fields.dart';
import 'document_editor.dart';
import 'document_dialogs.dart';
import 'bank_statement_import.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'ui/access_gate.dart';

class BankStatementMatchingScreen extends StatefulWidget {
  const BankStatementMatchingScreen({
    super.key,
    required this.api,
    required this.company,
  });
  final ErpApi api;
  final String company;
  @override
  State<BankStatementMatchingScreen> createState() =>
      _BankStatementMatchingState();
}

class _BankStatementMatchingState extends State<BankStatementMatchingScreen> {
  String bank = '', query = '';
  Map<String, dynamic>? line, payment;
  List<Map<String, dynamic>> statements = [], payments = [];
  DateTimeRange? dates;
  String? error, receipt;
  bool busy = false, canImport = false;
  int version = 0;
  bool posting = false;
  int postSequence = 0, contextVersion = 0;
  DialogRoute<bool>? reviewRoute;
  ModalRoute<dynamic>? dateRoute;
  ({String company, String statement, String payment})? attempted;
  Object get scope => (
    widget.api,
    widget.api.account,
    widget.company,
    widget.api.accessRevision,
    contextVersion,
  );
  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(accessChanged);
  }

  void accessChanged() {
    contextVersion++;
    dismissDocumentDialog(reviewRoute);
    dismissDocumentDialog(dateRoute);
    if (mounted) {
      setState(() {
        version++;
        line = payment = null;
        statements = [];
        payments = [];
        receipt = error = null;
        attempted = null;
        canImport = false;
      });
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(accessChanged);
    dismissDocumentDialog(reviewRoute);
    dismissDocumentDialog(dateRoute);
    super.dispose();
  }

  @override
  void didUpdateWidget(BankStatementMatchingScreen old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api || old.company != widget.company) {
      old.api.removeAccessListener(accessChanged);
      widget.api.addAccessListener(accessChanged);
      accessChanged();
      bank = query = '';
      dates = null;
      busy = posting = false;
      postSequence++;
    }
  }

  String iso(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> load({bool forPayments = false, bool verify = false}) async {
    final revision = ++version;
    final captured = scope;
    if (verify) {
      final ctx = await widget.api.workspaceContext(company: widget.company);
      if (!ctx.canMatchBankStatements) {
        throw const ErpException(
          'Bank matching is unavailable for this account.',
        );
      }
    }
    if (!mounted || revision != version || captured != scope) return;
    setState(() {
      busy = bank.isNotEmpty;
      error = null;
      payment = null;
      payments = [];
      if (!forPayments) {
        canImport = false;
        line = null;
        statements = [];
      }
      if (verify) {
        receipt = null;
      }
    });
    if (bank.isEmpty) return;
    try {
      final result = forPayments
          ? await widget.api.bankMatches(
              widget.company,
              bank,
              line!['name'],
              from: dates == null ? '' : iso(dates!.start),
              to: dates == null ? '' : iso(dates!.end),
            )
          : await widget.api.bankStatements(widget.company, bank, query);
      if (!mounted || revision != version || captured != scope) return;
      final rows = (result[forPayments ? 'payments' : 'statements'] as List)
          .map(objectMap)
          .toList();
      setState(() {
        if (forPayments) {
          payments = rows;
        } else {
          statements = rows;
          canImport = result['can_import'] == true;
        }
        busy = false;
      });
    } catch (e) {
      if (mounted && revision == version && captured == scope) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
      if (verify) {
        rethrow;
      }
    }
  }

  Future<void> dateRange() async {
    final captured = scope;
    final selected = await showDateRangePicker(
      context: context,
      builder: (dialog, child) {
        dateRoute = ModalRoute.of(dialog);
        return child!;
      },
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDateRange: dates,
      helpText: 'Select payment dates',
    );
    dateRoute = null;
    if (!mounted ||
        selected == null ||
        line == null ||
        captured != scope ||
        !widget.api.accessReady) {
      return;
    }
    if (selected.duration.inDays > 366) {
      setState(() => error = 'Choose a date range of up to one year.');
      return;
    }
    dates = selected;
    await load(forPayments: true);
  }

  Future<void> match() async {
    final statement = line, pay = payment;
    if (statement == null ||
        pay == null ||
        busy ||
        posting ||
        reviewRoute != null) {
      return;
    }
    final epoch = scope;
    final amount = math.min(
      double.parse(statement['unallocated_amount'].toString()),
      double.parse(pay['amount'].toString()),
    );
    final route = DialogRoute<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Match this bank statement line?'),
        content: Text(
          'Match ${statement['currency']} $amount from statement ${statement['name']} to payment ${pay['name']}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Match payment'),
          ),
        ],
      ),
    );
    reviewRoute = route;
    final yes = await Navigator.of(context).push(route);
    reviewRoute = null;
    if (!mounted ||
        yes != true ||
        busy ||
        epoch != scope ||
        !widget.api.accessReady ||
        !identical(statement, line) ||
        !identical(pay, payment)) {
      return;
    }
    final sequence = ++postSequence;
    setState(() {
      busy = posting = true;
      receipt = error = null;
      attempted = null;
    });
    try {
      final result = await widget.api.matchBankPayment(
        widget.company,
        bank,
        statement['name'],
        pay['name'],
        statement['unallocated_amount'].toString(),
        pay['amount'].toString(),
        from: dates == null ? '' : iso(dates!.start),
        to: dates == null ? '' : iso(dates!.end),
      );
      if (!mounted || epoch != scope) return;
      setState(
        () => receipt =
            'Matched ${statement['currency']} ${result['matched']}. Statement balance: ${result['remaining']}.${result['clearance_date'] == null ? '' : ' Payment cleared on ${result['clearance_date']}.'}',
      );
      await load();
    } catch (e) {
      if (mounted && epoch == scope) {
        setState(() {
          busy = false;
          final rejected =
              e is ErpException &&
              (e.validationRejected ||
                  e.staleDocument ||
                  e.permissionDenied ||
                  e.sessionExpired);
          attempted = rejected
              ? null
              : (
                  company: widget.company,
                  statement: statement['name'].toString(),
                  payment: pay['name'].toString(),
                );
          error = rejected
              ? '$e Refresh balances before matching again.'
              : '$e The outcome is not confirmed for ${statement['name']} → ${pay['name']}. Inspect the statement record and refresh balances before matching again.';
          line = payment = null;
          statements = [];
          payments = [];
        });
      }
    } finally {
      if (mounted && sequence == postSequence) {
        setState(() {
          posting = false;
          if (epoch == scope) busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () => load(verify: true),
    child: PopScope(
      canPop: !posting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Match bank statements')),
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
                  NativeScalarField(
                    field: NativeField.fromJson({
                      'fieldname': 'bank_account',
                      'label': 'Bank account',
                      'fieldtype': 'Link',
                      'options': 'Bank Account',
                    }),
                    scopeKey: scope,
                    value: bank,
                    linkType: 'Bank Account',
                    editable: !busy && !posting,
                    onLink: (t, q, _) => widget.api.searchLinks(t, q),
                    onChanged: (s) {
                      bank = s?.toString() ?? '';
                      query = '';
                      dates = null;
                      receipt = null;
                      load();
                    },
                  ),
                  if (bank.isNotEmpty && canImport)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import bank statement'),
                        onPressed: busy
                            ? null
                            : () async {
                                final posted = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BankStatementImport(
                                      api: widget.api,
                                      company: widget.company,
                                      bank: bank,
                                    ),
                                  ),
                                );
                                if (posted == true && mounted) {
                                  await load();
                                }
                              },
                      ),
                    ),
                  if (bank.isNotEmpty) ...[
                    TextField(
                      key: ValueKey(bank),
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Statement reference or description',
                      ),
                      onChanged: (s) => query = s,
                      onSubmitted: (_) => load(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy ? null : () => load(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh statement lines'),
                      ),
                    ),
                  ],
                  if (busy) const LinearProgressIndicator(),
                  if (receipt != null)
                    Semantics(liveRegion: true, child: Text(receipt!)),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline),
                          const SizedBox(width: 8),
                          Expanded(child: Text(error!)),
                        ],
                      ),
                    ),
                  if (attempted != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Check statement record'),
                        onPressed: busy
                            ? null
                            : () {
                                final source = attempted;
                                final api = widget.api;
                                if (source == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => DocumentEditor(
                                      api: api,
                                      doctype: 'Bank Transaction',
                                      name: source.statement,
                                      company: source.company,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                  if (statements.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey('statement-${statements.hashCode}'),
                      isExpanded: true,
                      initialValue: line?['name'],
                      decoration: const InputDecoration(
                        labelText: 'Unmatched statement line',
                      ),
                      items: [
                        for (final r in statements)
                          DropdownMenuItem(
                            value: r['name'] as String,
                            child: Text(
                              "${r['date']} · ${(r['deposit'] as num) > 0 ? 'Deposit' : 'Withdrawal'} ${r['currency']} ${r['unallocated_amount']} · ${r['name']}",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              line = statements.firstWhere(
                                (r) => r['name'] == v,
                              );
                              dates = null;
                              receipt = null;
                              load(forPayments: true);
                            },
                    ),
                  if (statements.isEmpty &&
                      bank.isNotEmpty &&
                      !busy &&
                      error == null)
                    const Text('No unmatched statement lines found.'),
                  if (line != null) ...[
                    const SizedBox(height: 8),
                    Text("${line!['description'] ?? ''}"),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : dateRange,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          dates == null
                              ? 'Payment dates · within 31 days'
                              : '${iso(dates!.start)} – ${iso(dates!.end)}',
                        ),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('bank-payment-${payments.hashCode}'),
                      isExpanded: true,
                      initialValue: payment?['name'],
                      decoration: const InputDecoration(
                        labelText: 'Posted payment',
                      ),
                      hint: Text(
                        busy
                            ? 'Loading…'
                            : payments.isEmpty
                            ? 'No matching payments'
                            : 'Select payment',
                      ),
                      items: [
                        for (final r in payments)
                          DropdownMenuItem(
                            value: r['name'] as String,
                            child: Text(
                              "${r['name']} · ${r['currency']} ${r['amount']}",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(
                              () => payment = payments.firstWhere(
                                (r) => r['name'] == v,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy || posting || payment == null
                          ? null
                          : match,
                      child: const Text('Review bank match'),
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
