import 'package:flutter/material.dart';

import '../../../core/ui/document_dialogs.dart';
import 'master_import_view_model.dart';

class MasterImportView extends StatefulWidget {
  const MasterImportView({
    super.key,
    required this.model,
    required this.protect,
  });
  final MasterImportViewModel model;
  final Widget Function(Widget, Future<void> Function()) protect;
  String get doctype => model.doctype;
  String get company => model.company;
  @override
  State<MasterImportView> createState() => _MasterImportViewState();
}

class _MasterImportViewState extends State<MasterImportView> {
  DialogRoute<bool>? _leaveRoute;
  Object? _leaveScope;
  bool get _busy => widget.model.busy;
  bool get _uncertain => widget.model.uncertain;
  String? get _filename => widget.model.filename;
  String? get _problem => widget.model.problem;
  bool get _alreadyImported => widget.model.preview?.alreadyImported == true;
  @override
  void initState() {
    super.initState();
    widget.model.addListener(_changed);
  }

  void _changed() {
    final scope = _leaveScope;
    if (scope != null && !widget.model.isCurrent(scope)) {
      dismissDocumentDialog(_leaveRoute);
    }
  }

  @override
  void didUpdateWidget(covariant MasterImportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
      dismissDocumentDialog(_leaveRoute);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    dismissDocumentDialog(_leaveRoute);
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy || _leaveRoute != null) {
      return;
    }
    if (!_uncertain) {
      Navigator.pop(context);
      return;
    }
    final model = widget.model, scope = widget.model.scope;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Check this import later?'),
        content: const Text(
          'The import may already be complete. Keep the original CSV file and choose it again to check its existing import receipt before importing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep checking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    _leaveRoute = route;
    _leaveScope = scope;
    final leave = await Navigator.of(context).push(route);
    if (identical(_leaveRoute, route)) {
      _leaveRoute = null;
      _leaveScope = null;
    }
    if (leave == true &&
        mounted &&
        model == widget.model &&
        model.isCurrent(scope)) {
      Navigator.pop(context);
    }
  }

  Future<void> _template() => widget.model.template();
  Future<void> _choose() => widget.model.choose();
  Future<void> _confirm() => widget.model.confirm();
  Future<void> _checkImport() => widget.model.check();
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => _content(context),
  );
  Widget _content(BuildContext context) {
    final data = widget.model.preview?.data;
    final done = widget.model.done;
    final count = widget.model.preview?.count ?? 0;
    final recordCount = '$count ${count == 1 ? "record" : "records"}';
    return widget.protect(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _leave();
        },
        child: Scaffold(
          appBar: AppBar(title: Text('Import ${widget.doctype} records')),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      widget.company,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add up to 200 new records from a UTF-8 CSV. Use the template headers, then review the file before importing.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _template,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Save template'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || _uncertain ? null : _choose,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _filename == null
                                ? 'Choose CSV'
                                : 'Choose another CSV',
                          ),
                        ),
                      ],
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_filename != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_filename!),
                      ),
                    if (_problem != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _problem!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (_uncertain) ...[
                      const Text(
                        'Import outcome not confirmed. Keep this file unchanged while checking.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _busy ? null : _checkImport,
                            child: const Text('Check import outcome'),
                          ),
                          TextButton(
                            onPressed: widget.model.canConfirm
                                ? _confirm
                                : null,
                            child: const Text('Retry same import'),
                          ),
                        ],
                      ),
                    ],
                    if (data != null && !done) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Preview · $recordCount',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (count > 5) const Text('First five rows'),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final column in data['columns'] as List)
                              DataColumn(
                                label: Text(
                                  column.toString().replaceAll('_', ' '),
                                ),
                              ),
                          ],
                          rows: [
                            for (final row in data['sample'] as List)
                              DataRow(
                                cells: [
                                  for (final value in row as List)
                                    DataCell(Text(value.toString())),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (!_uncertain)
                        FilledButton(
                          onPressed: widget.model.canConfirm ? _confirm : null,
                          child: Text('Import $recordCount'),
                        ),
                    ],
                    if (done)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _alreadyImported
                              ? 'Already imported · $recordCount.'
                              : 'Imported $recordCount.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      widget.model.revalidate,
    );
  }
}
