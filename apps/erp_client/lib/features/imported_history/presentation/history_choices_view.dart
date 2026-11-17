import 'dart:async';

import 'package:flutter/material.dart';

import '../models/history_filter_values.dart';
import 'history_choices_view_model.dart';

class HistoryChoicesView extends StatefulWidget {
  const HistoryChoicesView({super.key, required this.model});
  final HistoryChoicesViewModel model;
  @override
  State<HistoryChoicesView> createState() => _HistoryChoicesViewState();
}

class _HistoryChoicesViewState extends State<HistoryChoicesView> {
  Timer? timer;
  int get start => widget.model.start;
  bool get loading => widget.model.loading;
  bool get more => widget.model.hasMore;
  String? get error => widget.model.error;
  List<Map<String, dynamic>> get rows => widget.model.rows;
  @override
  void didUpdateWidget(covariant HistoryChoicesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model || !widget.model.valid) timer?.cancel();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _search(String value) {
    timer?.cancel();
    final model = widget.model;
    model.beginSearch();
    timer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && identical(model, widget.model) && model.valid) {
        model.search(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => AlertDialog(
      title: Text(historyFilterLabels[widget.model.field]!),
      content: SizedBox(
        width: 460,
        height: 340,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search saved values',
              ),
              onChanged: _search,
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            Expanded(
              child: ListView(
                children: [
                  for (final row in rows)
                    ListTile(
                      title: Text(row['label'] as String),
                      onTap: () {
                        if (widget.model.canChoose(row)) {
                          Navigator.pop(context, row);
                        }
                      },
                    ),
                  if (!loading && rows.isEmpty && error == null)
                    const ListTile(title: Text('No saved values match.')),
                ],
              ),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: loading || start == 0
                      ? null
                      : widget.model.previousPage,
                  child: const Text('Previous choices'),
                ),
                TextButton(
                  onPressed: loading || !more ? null : widget.model.nextPage,
                  child: const Text('Next choices'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
