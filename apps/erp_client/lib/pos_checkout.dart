import 'dart:math';

import 'package:flutter/material.dart';

import 'design.dart';
import 'document_fields.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'ui/access_gate.dart';
import 'widgets.dart';

Future<bool> _confirmPosLeave(
  BuildContext context, {
  required bool busy,
  required bool attempted,
  required bool dirty,
  required bool refund,
}) async {
  if (!busy && !attempted && !dirty) return true;
  final operation = refund ? 'refund' : 'checkout';
  return await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(
            busy
                ? 'Operation in progress'
                : attempted
                ? 'Confirm the $operation outcome'
                : 'Discard ${refund ? 'refund' : 'sale'} changes?',
          ),
          content: Text(
            busy
                ? 'This operation is still in progress. Keep this screen open until it finishes.'
                : attempted
                ? 'The $operation may already have been recorded. Use Retry same $operation to confirm its outcome before leaving.'
                : 'Your unsaved ${refund ? 'refund' : 'sale'} entry will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing'),
            ),
            if (!busy && !attempted)
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Discard changes'),
              ),
          ],
        ),
      ) ??
      false;
}

class PosCheckoutScreen extends StatefulWidget {
  const PosCheckoutScreen({
    super.key,
    required this.api,
    required this.company,
    this.onAccount,
  });
  final ErpApi api;
  final VoidCallback? onAccount;
  final String company;
  @override
  State<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends State<PosCheckoutScreen> {
  late Future<Map<String, dynamic>> register;
  late Object _scope;
  Object get _currentScope => (widget.api, widget.api.account, widget.company);
  bool askingLeave = false;
  int saleRevision = 0, generation = 0;
  bool get dirty =>
      cart.isNotEmpty ||
      customer.trim().isNotEmpty ||
      item.trim().isNotEmpty ||
      qty.text.trim() != '1' ||
      quote != null;

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> leave({VoidCallback? action}) async {
    if (askingLeave) return;
    askingLeave = true;
    final scope = _scope, at = generation;
    final allowed = await _confirmPosLeave(
      context,
      busy: busy,
      attempted: attempted,
      dirty: dirty,
      refund: false,
    );
    askingLeave = false;
    if (!mounted || scope != _scope || at != generation || !allowed) return;
    if (action != null) {
      setState(() {
        saleRevision++;
        cart.clear();
        customer = '';
        item = '';
        qty.text = '1';
        resetReview();
      });
      action();
    } else {
      Navigator.pop(context);
    }
  }

  void removeItem(String name) {
    if (busy || attempted || quote != null) return;
    final index = cart.keys.toList().indexOf(name);
    final quantity = cart[name];
    if (index < 0 || quantity == null) return;
    final scope = _scope,
        revision = widget.api.accessRevision,
        sale = saleRevision;
    setState(() => cart.remove(name));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name removed from this sale.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted ||
                scope != _scope ||
                revision != widget.api.accessRevision ||
                !widget.api.accessReady ||
                sale != saleRevision ||
                busy ||
                attempted ||
                quote != null ||
                cart.containsKey(name)) {
              return;
            }
            final rows = cart.entries.toList()
              ..insert(index.clamp(0, cart.length), MapEntry(name, quantity));
            setState(() {
              cart
                ..clear()
                ..addEntries(rows);
            });
          },
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PosCheckoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scope != _currentScope) {
      _scope = _currentScope;
      generation++;
      saleRevision++;
      cart.clear();
      customer = '';
      item = '';
      qty.text = '1';
      float.text = '0';
      profile = null;
      lastSale = null;
      error = null;
      notice = null;
      busy = false;
      resetReview();
      register = widget.api.posRegister(widget.company);
    }
  }

  String? profile, error, notice, token;
  String customer = '', item = '';
  final float = TextEditingController(text: '0');
  final qty = TextEditingController(text: '1');
  final cart = <String, String>{};
  String? lastSale;
  Map<String, dynamic>? quote;
  bool busy = false, attempted = false, counting = false;
  List<Map<String, dynamic>> get items => [
    for (final e in cart.entries) {'item': e.key, 'qty': e.value},
  ];
  @override
  void initState() {
    super.initState();
    _scope = _currentScope;
    qty.addListener(_changed);
    register = widget.api.posRegister(widget.company);
  }

  @override
  void dispose() {
    float.dispose();
    qty.removeListener(_changed);
    qty.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    final scope = _scope, at = generation;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted && scope == _scope && at == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && scope == _scope && at == generation) {
        setState(() => busy = false);
      }
    }
  }

  void resetReview() {
    quote = null;
    token = null;
    attempted = false;
  }

  void reload() =>
      setState(() => register = widget.api.posRegister(widget.company));

  Future<void> revalidate() async {
    final scope = _scope, revision = widget.api.accessRevision, at = generation;
    final result = widget.api.posRegister(widget.company);
    setState(() {
      register = result;
      notice = null;
      error = null;
    });
    await result;
    if (mounted &&
        scope == _scope &&
        at == generation &&
        revision == widget.api.accessRevision &&
        !attempted) {
      setState(resetReview);
    }
  }

  Future<void> review(String opening) async {
    final scope = _scope, revision = widget.api.accessRevision, at = generation;
    final result = await widget.api.posQuote(
      widget.company,
      opening,
      customer,
      items,
    );
    if (!mounted ||
        scope != _scope ||
        at != generation ||
        revision != widget.api.accessRevision) {
      return;
    }
    setState(() {
      quote = result;
      token = _reference();
    });
  }

  Future<void> pay(String opening) async {
    final scope = _scope, at = generation;
    final total = quote!['amount'].toString();
    setState(() => attempted = true);
    try {
      final receipt = await widget.api.posCheckout(
        widget.company,
        opening,
        customer,
        items,
        total,
        token!,
      );
      if (!mounted || scope != _scope || at != generation) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() {
        saleRevision++;
        notice =
            '${receipt['doctype']} ${receipt['invoice']} · ${receipt['currency']} ${receipt['amount']} received in cash.';
        lastSale = receipt['invoice'] as String;
        cart.clear();
        customer = '';
        item = '';
        qty.text = '1';
        resetReview();
      });
    } on ErpException catch (e) {
      // A rejected request rolled back. An interrupted request keeps its sale
      // reference and locked cart so the same checkout can be safely recovered.
      if (mounted &&
          scope == _scope &&
          at == generation &&
          e.validationRejected) {
        setState(resetReview);
      }
      rethrow;
    }
  }

  Future<void> refund(String opening) async {
    final scope = _scope, at = generation;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _RefundScreen(
          api: widget.api,
          company: widget.company,
          opening: opening,
          initial: lastSale ?? '',
        ),
      ),
    );
    if (result != null && mounted && scope == _scope && at == generation) {
      setState(() => notice = result);
    }
  }

  Future<void> close(String opening) async {
    final scope = _scope, at = generation;
    final summary = await widget.api.posClosing(widget.company, opening);
    if (!mounted || scope != _scope || at != generation) return;
    setState(() => counting = true);
    final counted = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => _CountCash(summary: summary),
    );
    if (!mounted || scope != _scope || at != generation) return;
    setState(() => counting = false);
    if (counted == null) return;
    final result = await widget.api.posCloseShift(
      widget.company,
      opening,
      counted,
      summary['revision'] as String,
    );
    if (!mounted || scope != _scope || at != generation) return;
    setState(() {
      saleRevision++;
      notice = 'Closing entry ${result['closing']} · ${result['status']}';
      resetReview();
      cart.clear();
      customer = '';
      item = '';
    });
    reload();
  }

  Widget link(String type, String value, ValueChanged<String> change) =>
      NativeScalarField(
        key: ValueKey(type),
        field: NativeField.fromJson({
          'fieldname': type,
          'label': type,
          'fieldtype': 'Link',
          'options': type,
        }),
        linkType: type,
        value: value,
        editable: !busy && quote == null,
        onLink: (type, q, _) => widget.api.searchLinks(type, q),
        onChanged: (v) => setState(() => change(v?.toString().trim() ?? '')),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !attempted && !dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: AccessGate(
      key: ObjectKey(widget.api),
      api: widget.api,
      revalidate: revalidate,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Point of sale'),
          actions: [
            if (widget.onAccount != null)
              IconButton(
                tooltip: 'Account',
                onPressed: () => leave(action: widget.onAccount),
                icon: const Icon(Icons.person_outline),
              ),
          ],
        ),
        body: WorkspaceBackdrop(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 740),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Display(widget.company, size: 30),
                    if (notice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(notice!),
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(liveRegion: true, child: Text(error!)),
                      ),
                    const SizedBox(height: 12),
                    if (busy && !counting) const LinearProgressIndicator(),
                    FutureBuilder<Map<String, dynamic>>(
                      future: register,
                      builder: (context, state) {
                        if (state.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (state.hasError) {
                          return MessagePanel(
                            title: 'Could not load register',
                            message: state.error.toString(),
                            label: 'Retry',
                            action: reload,
                          );
                        }
                        final data = state.requireData;
                        final opening = data['opening'] as String?;
                        if (opening == null) {
                          final options = List<String>.from(data['profiles']);
                          if (options.isEmpty) {
                            if (data['can_configure'] == true) {
                              return Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Display(
                                      'Set up your register',
                                      size: 26,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Use the company warehouse, selling price list and cash account. Staff invited as cashiers can use this register.',
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => run(() async {
                                              await widget.api.posConfigure(
                                                widget.company,
                                              );
                                              if (mounted) reload();
                                            }),
                                      child: const Text(
                                        'Create company register',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const Text(
                              'No enabled POS profile is available. Ask your company owner to set up a register for your cashier account.',
                            );
                          }
                          final selected = options.contains(profile)
                              ? profile
                              : options.first;
                          return Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Display('Open shift', size: 26),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: selected,
                                  decoration: const InputDecoration(
                                    labelText: 'POS profile',
                                  ),
                                  items: [
                                    for (final option in options)
                                      DropdownMenuItem(
                                        value: option,
                                        child: Text(option),
                                      ),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (s) => setState(() => profile = s),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: float,
                                  enabled: !busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Opening cash',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => run(() async {
                                          await widget.api.posOpenShift(
                                            widget.company,
                                            selected!,
                                            float.text.trim(),
                                          );
                                          if (mounted) reload();
                                        }),
                                  child: const Text('Open register'),
                                ),
                              ],
                            ),
                          );
                        }
                        return Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Display(data['profile'] as String, size: 26),
                              Text('Shift $opening'),
                              const SizedBox(height: 16),
                              link('Customer', customer, (s) => customer = s),
                              const SizedBox(height: 12),
                              if (quote == null) ...[
                                link('Item', item, (s) => item = s),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: qty,
                                  enabled: !busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Quantity',
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add to sale'),
                                    onPressed: busy || item.isEmpty
                                        ? null
                                        : () {
                                            final n = double.tryParse(
                                              qty.text.trim(),
                                            );
                                            if (n == null ||
                                                !n.isFinite ||
                                                n <= 0) {
                                              setState(
                                                () => error = 'Enter a positive quantity.',
                                              );
                                              return;
                                            }
                                            setState(() {
                                              cart[item] =
                                                  (double.parse(
                                                            cart[item] ?? '0',
                                                          ) +
                                                          n)
                                                      .toString();
                                              item = '';
                                              qty.text = '1';
                                              error = null;
                                            });
                                          },
                                  ),
                                ),
                                for (final row in cart.entries)
                                  ListTile(
                                    title: Text(row.key),
                                    subtitle: Text('Quantity ${row.value}'),
                                    trailing: IconButton(
                                      tooltip: 'Remove ${row.key}',
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: busy
                                          ? null
                                          : () => removeItem(row.key),
                                    ),
                                  ),
                                FilledButton(
                                  onPressed:
                                      busy || cart.isEmpty || customer.isEmpty
                                      ? null
                                      : () => run(() => review(opening)),
                                  child: const Text('Review sale'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: busy || cart.isNotEmpty
                                      ? null
                                      : () => refund(opening),
                                  icon: const Icon(
                                    Icons.assignment_return_outlined,
                                  ),
                                  label: const Text('Refund a sale'),
                                ),
                                TextButton(
                                  onPressed: busy || cart.isNotEmpty
                                      ? null
                                      : () => run(() => close(opening)),
                                  child: const Text('Close shift'),
                                ),
                              ] else ...[
                                for (final row in quote!['items'] as List)
                                  ListTile(
                                    title: Text(row['item']),
                                    subtitle: Text(
                                      '${row['qty']} × ${row['rate']}',
                                    ),
                                    trailing: Text('${row['amount']}'),
                                  ),
                                const Divider(),
                                Text(
                                  'Cash due · ${quote!['currency']} ${quote!['amount']}',
                                  style: displayStyle(26),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => run(() => pay(opening)),
                                  child: Text(
                                    attempted
                                        ? 'Retry same checkout'
                                        : 'Confirm cash received',
                                  ),
                                ),
                                if (!attempted)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => setState(resetReview),
                                    child: const Text('Edit sale'),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _reference() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _RefundScreen extends StatefulWidget {
  const _RefundScreen({
    required this.api,
    required this.company,
    required this.opening,
    required this.initial,
  });
  final ErpApi api;
  final String company, opening, initial;
  @override
  State<_RefundScreen> createState() => _RefundState();
}

class _RefundState extends State<_RefundScreen> {
  bool askingLeave = false;
  bool get dirty =>
      summary != null || invoice.text.trim() != widget.initial.trim();
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    invoice.addListener(_changed);
  }

  Future<void> leave() async {
    if (askingLeave) return;
    askingLeave = true;
    final allowed = await _confirmPosLeave(
      context,
      busy: busy,
      attempted: attempted,
      dirty: dirty,
      refund: true,
    );
    askingLeave = false;
    if (mounted && allowed) Navigator.pop(context);
  }

  late final TextEditingController invoice = TextEditingController(
    text: widget.initial,
  );
  Map<String, dynamic>? summary;
  String? token, error;
  bool busy = false, attempted = false;
  @override
  void dispose() {
    invoice.removeListener(_changed);
    invoice.dispose();
    super.dispose();
  }

  Future<void> act() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (summary == null) {
        final values = await widget.api.posRefundReview(
          widget.company,
          widget.opening,
          invoice.text.trim(),
        );
        if (mounted) {
          setState(() {
            summary = values;
            token = _reference();
            error = null;
          });
        }
      } else {
        setState(() => attempted = true);
        final result = await widget.api.posRefund(
          widget.company,
          widget.opening,
          invoice.text.trim(),
          summary!['amount'].toString(),
          token!,
        );
        if (mounted) {
          Navigator.pop(
            context,
            'Cash refund ${result['invoice']} · ${summary!['currency']} ${summary!['amount']} against ${invoice.text.trim()}.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (e is ErpException && e.validationRejected) {
            summary = null;
            token = null;
            attempted = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !attempted && !dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: AccessGate(
      key: ObjectKey(widget.api),
      api: widget.api,
      revalidate: () async {
        await widget.api.posRegister(widget.company);
        if (mounted && !attempted) {
          setState(() {
            summary = null;
            token = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Refund a sale')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Display('Full receipt refund', size: 26),
                        const SizedBox(height: 8),
                        const Text(
                          'Return all items on an original cash receipt from this register.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: invoice,
                          enabled: !busy && summary == null,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Original invoice number',
                          ),
                          onSubmitted: (_) => act(),
                        ),
                        if (summary != null) ...[
                          const SizedBox(height: 12),
                          Text('Customer · ${summary!['customer']}'),
                          for (final row in summary!['items'] as List)
                            ListTile(
                              title: Text(row['item']),
                              subtitle: Text('Quantity ${row['qty']}'),
                              trailing: Text('${row['amount']}'),
                            ),
                          Text(
                            'Cash refund · ${summary!['currency']} ${summary!['amount']}',
                            style: displayStyle(25),
                          ),
                        ],
                        if (error != null)
                          Semantics(liveRegion: true, child: Text(error!)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: busy ? null : act,
                          child: Text(
                            summary == null
                                ? 'Review refund'
                                : attempted
                                ? 'Retry same refund'
                                : 'Confirm cash refund',
                          ),
                        ),
                        if (summary != null && !attempted)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    summary = null;
                                    token = null;
                                  }),
                            child: const Text('Change receipt'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CountCash extends StatefulWidget {
  const _CountCash({required this.summary});
  final Map<String, dynamic> summary;
  @override
  State<_CountCash> createState() => _CountCashState();
}

class _CountCashState extends State<_CountCash> {
  final key = GlobalKey<FormState>();
  final amounts = <String, String>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Close shift'),
    content: Form(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.summary['sales']} posted sales'),
          const SizedBox(height: 12),
          for (final row in widget.summary['payments'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: 'Counted ${row['mode']}',
                  helperText: 'Expected ${row['expected']}',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (s) => amounts[row['mode']] = s.trim(),
                validator: (s) {
                  final n = double.tryParse(s ?? '');
                  return n != null && n.isFinite && n >= 0
                      ? null
                      : 'Enter the amount counted.';
                },
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep shift open'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate()) Navigator.pop(context, amounts);
        },
        child: const Text('Confirm close'),
      ),
    ],
  );
}
