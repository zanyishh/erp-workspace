import 'package:flutter/material.dart';

import '../models/operation_reference.dart';
import 'pending_operations_view_model.dart';

class PendingOperationsView extends StatefulWidget {
  const PendingOperationsView({
    super.key,
    required this.model,
    required this.company,
    required this.open,
    required this.protect,
  });
  final PendingOperationsViewModel model;
  final String company;
  final Future<void> Function(OperationTarget target) open;
  final Widget Function(Widget child, Future<void> Function() reload) protect;
  @override
  State<PendingOperationsView> createState() => _PendingOperationsViewState();
}

class _PendingOperationsViewState extends State<PendingOperationsView> {
  @override
  void initState() {
    super.initState();
    _run(widget.model.load);
  }

  @override
  void didUpdateWidget(covariant PendingOperationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) _run(widget.model.load);
  }

  Future<void> _run(Future<void> Function() command) async {
    final model = widget.model;
    final next = command();
    if (mounted) setState(() {});
    try {
      await next;
    } finally {
      if (mounted && identical(model, widget.model)) setState(() {});
    }
  }

  Future<void> _revalidate() => _run(widget.model.revalidate);
  Widget entry(OperationReference row) {
    final model = widget.model;
    final state = row.state, result = row.result, target = row.target;
    final name = row.savedName;
    final waiting = model.isWorking(row.requestId);
    final reconciliation = model.reconciliationNotice(row);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.title(row),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Semantics(liveRegion: true, child: Text(model.statusLabel(row))),
            if (name != null) SelectableText(name),
            if (result.event != null)
              SelectableText('Recorded event · ${result.event}'),
            if (reconciliation != null) Text(reconciliation),
            Text(row.creation),
            const SizedBox(height: 6),
            SelectableText(
              'Reference · ${row.requestId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (model.canClose(row))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'The request may still be finishing. Check its status, or close it before creating a replacement. Closing waits for any active write and prevents an unposted request from posting later.',
                ),
              ),
            if (waiting) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: waiting
                      ? null
                      : () => _run(() => model.checkStatus(row.requestId)),
                  child: const Text('Check status'),
                ),
                if (model.canClose(row))
                  OutlinedButton(
                    onPressed: waiting
                        ? null
                        : () => _run(() => model.closeUnposted(row.requestId)),
                    child: const Text('Close unposted request'),
                  ),
                if (state == 'completed' && target != null)
                  OutlinedButton(
                    onPressed: waiting ? null : () => widget.open(target),
                    child: const Text('Open saved record'),
                  ),
                if (model.canDismiss(row))
                  TextButton(
                    onPressed: waiting
                        ? null
                        : () => _run(() => model.dismiss(row.requestId)),
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return widget.protect(
      Scaffold(
        appBar: AppBar(
          title: const Text('Pending operations'),
          actions: [
            IconButton(
              tooltip: 'Refresh pending operations',
              onPressed: model.loading ? null : () => _run(model.load),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.company,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Check interrupted requests from this account. No action is posted automatically.',
                ),
                if (model.loading) const LinearProgressIndicator(),
                if (model.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.error!),
                        TextButton(
                          onPressed: () => _run(model.load),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (!model.loading && model.error == null && model.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      model.page == 0 && !model.more
                          ? 'No operations need attention.'
                          : 'No operations on this page.',
                    ),
                  ),
                for (final row in model.rows) entry(row),
                if (model.page > 0 || model.more)
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: model.loading || model.page == 0
                            ? null
                            : () => _run(model.previousPage),
                        child: const Text('Previous'),
                      ),
                      Text('Page ${model.page + 1}'),
                      TextButton(
                        onPressed: model.loading || !model.more
                            ? null
                            : () => _run(model.nextPage),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      _revalidate,
    );
  }
}
