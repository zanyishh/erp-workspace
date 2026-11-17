import 'dart:async';

import 'package:flutter/material.dart';

import 'erp_api.dart';
import 'knitting_models.dart';

/// Each register owns a bounded page. Responses from an older filter or access
/// revision never replace the current company's records.
class KnittingRegisterPage extends StatefulWidget {
  const KnittingRegisterPage({
    super.key,
    required this.api,
    required this.snapshot,
    required this.collection,
    required this.builder,
    this.job,
    this.query = '',
    this.state,
    this.productionDate,
    this.fromDate,
    this.toDate,
    this.customer,
    this.category,
    this.start = 0,
    required this.onPage,
  });
  final ErpApi api;
  final KnittingSnapshot snapshot;
  final String collection, query;
  final String? job,
      state,
      productionDate,
      fromDate,
      toDate,
      customer,
      category;
  final int start;
  final ValueChanged<int> onPage;
  final Widget Function(
    List<Map<String, dynamic>> rows,
    Widget controls,
    bool loading,
  )
  builder;

  @override
  State<KnittingRegisterPage> createState() => _KnittingRegisterPageState();
}

class _KnittingRegisterPageState extends State<KnittingRegisterPage> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? page;
  String? error;
  bool loading = false;
  int generation = 0;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(invalidate);
    reset();
  }

  @override
  void didUpdateWidget(covariant KnittingRegisterPage old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api) {
      old.api.removeAccessListener(invalidate);
      widget.api.addAccessListener(invalidate);
    }
    if (old.snapshot != widget.snapshot ||
        old.api != widget.api ||
        old.collection != widget.collection ||
        old.job != widget.job ||
        old.query != widget.query ||
        old.state != widget.state ||
        old.productionDate != widget.productionDate ||
        old.fromDate != widget.fromDate ||
        old.toDate != widget.toDate ||
        old.customer != widget.customer ||
        old.category != widget.category ||
        old.start != widget.start) {
      reset(delayed: old.query != widget.query);
    }
  }

  void invalidate() {
    if (!mounted) return;
    generation++;
    debounce?.cancel();
    setState(() {
      rows = [];
      page = null;
      loading = false;
      error = 'Access changed. Refresh this workspace.';
    });
  }

  void reset({bool delayed = false}) {
    generation++;
    debounce?.cancel();
    error = null;
    rows = [];
    page = null;
    if (widget.start == 0 &&
        widget.query.trim().isEmpty &&
        widget.state == null &&
        widget.productionDate == null &&
        widget.fromDate == null &&
        widget.toDate == null &&
        widget.customer == null &&
        widget.category == null &&
        widget.snapshot.data['scope_job'] == widget.job) {
      page = widget.snapshot.page(widget.collection);
      if (page != null) {
        rows = widget.snapshot.rows(widget.collection);
        loading = false;
        return;
      }
    }
    loading = true;
    if (delayed) {
      debounce = Timer(const Duration(milliseconds: 250), load);
    } else {
      load();
    }
  }

  Future<void> load() async {
    final token = ++generation;
    final access = widget.api.accessRevision;
    final company = widget.snapshot.company;
    final collection = widget.collection;
    final job = widget.job;
    try {
      final value = await widget.api.knittingRegister(
        company,
        collection,
        job: job,
        start: widget.start,
        query: widget.query.trim(),
        state: widget.state,
        productionDate: widget.productionDate,
        fromDate: widget.fromDate,
        toDate: widget.toDate,
        customer: widget.customer,
        category: widget.category,
      );
      if (!mounted ||
          token != generation ||
          access != widget.api.accessRevision) {
        return;
      }
      final meta = value['page'];
      final items = value['rows'];
      if (value['version'] != 1 ||
          value['company'] != company ||
          value['collection'] != collection ||
          value['scope_job'] != job ||
          value['state'] != widget.state ||
          (const {'jobs', 'estimates'}.contains(collection) &&
              (value['from_date'] != widget.fromDate ||
                  value['to_date'] != widget.toDate)) ||
          (collection == 'jobs' && value['customer'] != widget.customer) ||
          (collection == 'masters' && value['category'] != widget.category) ||
          meta is! Map ||
          meta['start'] != widget.start ||
          meta['limit'] != 100 ||
          meta['has_more'] is! bool ||
          meta['total'] is! int ||
          items is! List ||
          items.length > 100 ||
          items.any((r) => r is! Map)) {
        throw const ErpException(
          'The register returned an unexpected page. Refresh and try again.',
        );
      }
      setState(() {
        rows = items.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        page = Map<String, dynamic>.from(meta);
        loading = false;
      });
    } catch (e) {
      if (mounted &&
          token == generation &&
          access == widget.api.accessRevision) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    widget.api.removeAccessListener(invalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final total = page?['total'];
    final limit = (page?['limit'] as int?) ?? 100;
    final controls = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading register'),
          if (error != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(error!),
                TextButton(
                  onPressed: () => setState(() => reset()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                loading
                    ? 'Loading records…'
                    : total == null
                    ? 'Records unavailable'
                    : rows.isEmpty
                    ? '0 of $total records'
                    : '${start + 1}–${start + rows.length} of $total records',
              ),
              OutlinedButton.icon(
                key: ValueKey('${widget.collection}-previous'),
                onPressed: loading || start == 0
                    ? null
                    : () => widget.onPage((start - limit).clamp(0, start)),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Previous'),
              ),
              OutlinedButton.icon(
                key: ValueKey('${widget.collection}-next'),
                onPressed: loading || page?['has_more'] != true
                    ? null
                    : () => widget.onPage(start + limit),
                icon: const Icon(Icons.chevron_right, size: 18),
                iconAlignment: IconAlignment.end,
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
    return widget.builder(rows, controls, loading);
  }
}

class KnittingSourcesDialog extends StatefulWidget {
  const KnittingSourcesDialog({
    super.key,
    required this.api,
    required this.snapshot,
    required this.collection,
    required this.title,
    required this.row,
    this.productionDate,
    this.state,
  });
  final ErpApi api;
  final KnittingSnapshot snapshot;
  final String collection, title;
  final String? productionDate, state;
  final Widget Function(Map<String, dynamic>) row;
  @override
  State<KnittingSourcesDialog> createState() => _KnittingSourcesDialogState();
}

class _KnittingSourcesDialogState extends State<KnittingSourcesDialog> {
  int start = 0;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      height: MediaQuery.sizeOf(context).height * .5,
      child: KnittingRegisterPage(
        api: widget.api,
        snapshot: widget.snapshot,
        collection: widget.collection,
        productionDate: widget.productionDate,
        state: widget.state,
        start: start,
        onPage: (value) => setState(() => start = value),
        builder: (rows, controls, loading) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls,
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, index) => widget.row(rows[index]),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
