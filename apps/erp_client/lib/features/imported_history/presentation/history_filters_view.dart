import 'package:flutter/material.dart';

import '../models/history_filter_values.dart';
import 'history_filter_text.dart';
import 'history_filters_view_model.dart';

class HistoryFiltersView extends StatefulWidget {
  const HistoryFiltersView({
    super.key,
    required this.model,
    required this.choose,
  });
  final HistoryFiltersViewModel model;
  final Future<Map<String, dynamic>?> Function(HistoryChoiceIntent) choose;
  @override
  State<HistoryFiltersView> createState() => _HistoryFiltersViewState();
}

class _HistoryFiltersViewState extends State<HistoryFiltersView> {
  late final from = TextEditingController(text: widget.model.from);
  late final to = TextEditingController(text: widget.model.to);
  bool get valid => widget.model.valid;
  String get basis => widget.model.basis;
  String? get error => widget.model.error;
  Map<String, dynamic> get selected => widget.model.selected;
  Map<String, String> get labels => widget.model.labels;
  @override
  void didUpdateWidget(covariant HistoryFiltersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      from.text = widget.model.from;
      to.text = widget.model.to;
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  Future<void> choose(String field) async {
    final model = widget.model,
        intent = widget.model.prepareChoice(field, from.text, to.text);
    if (intent == null) return;
    final row = await widget.choose(intent);
    if (mounted && identical(model, widget.model) && row != null) {
      model.acceptChoice(intent, row);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => !valid
        ? AlertDialog(
            title: const Text('History access changed'),
            content: const Text('Reopen the filters after access is checked.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          )
        : AlertDialog(
            scrollable: true,
            title: const Text('Filter original records'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(basis),
                      initialValue: basis,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Date basis',
                      ),
                      items: [
                        for (final e in historyDateLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        widget.model.selectBasis(v);
                        if (v == 'no_original') {
                          from.clear();
                          to.clear();
                        }
                      },
                    ),
                    if (basis != 'no_original') ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('history-from-date'),
                        controller: from,
                        decoration: const InputDecoration(
                          labelText: 'From · YYYY-MM-DD',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('history-to-date'),
                        controller: to,
                        decoration: const InputDecoration(
                          labelText: 'Through · YYYY-MM-DD',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Effective date includes approved openings. No original date also includes these openings. Party names and order values match exactly as saved. Job order selects one original order.',
                    ),
                    for (final field in widget.model.fields.where(
                      historyFilterLabels.containsKey,
                    )) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => choose(field),
                              child: Text(
                                selected.containsKey(field)
                                    ? '${historyFilterLabels[field]}: ${historyFilterValue(field, selected[field], labels)}'
                                    : historyFilterLabels[field]!,
                              ),
                            ),
                          ),
                          if (selected.containsKey(field))
                            IconButton(
                              tooltip: 'Clear ${historyFilterLabels[field]}',
                              onPressed: () => widget.model.clear(field),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ],
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final result = widget.model.apply(from.text, to.text);
                  if (result != null) Navigator.pop(context, result);
                },
                child: const Text('Apply filters'),
              ),
            ],
          ),
  );
}
