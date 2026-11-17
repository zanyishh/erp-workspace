import '../../../core/ui/document_dialogs.dart';
import '../models/catalog_models.dart';
import 'native_tree_view_model.dart';
import '../../../core/ui/record_icon.dart';

import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../../../core/models/native_models.dart';
import '../../../core/ui/widgets.dart';

class NativeTreeView extends StatefulWidget {
  const NativeTreeView({
    super.key,
    required this.model,
    required this.open,
    required this.browse,
    required this.protect,
    this.parentTitle,
  });
  final NativeTreeViewModel model;
  final Future<void> Function(String?) open;
  final Future<void> Function(NativeTreeNode) browse;
  final Widget Function(Widget, Future<void> Function()) protect;
  final String? parentTitle;
  NativeType get type => model.type;
  String? get parent => model.parent;
  @override
  State<NativeTreeView> createState() => _NativeTreeViewState();
}

class _NativeTreeViewState extends State<NativeTreeView> {
  int get _start => widget.model.start;
  bool get _changing => widget.model.changing;
  Future<NativeTreePage> get _future => widget.model.result;
  Route<dynamic>? _changeRoute;
  Object? _dialogToken;
  Object? _dialogScope;
  @override
  void didUpdateWidget(covariant NativeTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model ||
        _dialogScope != null && _dialogScope != widget.model.scope) {
      dismissDocumentDialog(_changeRoute);
    }
  }

  @override
  void dispose() {
    dismissDocumentDialog(_changeRoute);
    super.dispose();
  }

  void _reload() => setState(() {
    widget.model.reload();
  });
  void _page(bool forward) => setState(() {
    if (forward) {
      widget.model.nextPage();
    } else {
      widget.model.previousPage();
    }
  });
  Future<void> _open({String? name}) async {
    final model = widget.model;
    if (!model.canOpen(name)) {
      return;
    }
    await widget.open(name);
    if (mounted && model == widget.model) {
      _reload();
    }
  }

  Future<void> _browse(NativeTreeNode node) async {
    final model = widget.model;
    if (!model.canOpen(node.name)) {
      return;
    }
    await widget.browse(node);
    if (mounted && model == widget.model) {
      _reload();
    }
  }

  Future<void> _change(NativeTreeNode node, String action) async {
    if (_dialogToken != null) {
      return;
    }
    final model = widget.model, scope = widget.model.scope;
    final intent = model.prepareChange(node, action);
    if (intent == null) {
      return;
    }
    final rename = action == 'rename', name = node.name;
    var newName = '';
    final token = Object(), ownerRoute = ModalRoute.of(context);
    _dialogToken = token;
    _dialogScope = scope;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) {
        final route = ModalRoute.of(dialog);
        if (identical(_dialogToken, token) &&
            route != null &&
            !identical(route, ownerRoute)) {
          _changeRoute = route;
        }
        if (!mounted || model != widget.model || scope != model.scope) {
          dismissDocumentDialog(_changeRoute);
          return const SizedBox.shrink();
        }
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(rename ? 'Rename $name' : 'Delete $name?'),
            content: rename
                ? TextField(
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'New name'),
                    onChanged: (value) =>
                        setDialogState(() => newName = value.trim()),
                  )
                : Text(
                    'This removes the ${model.type.name.toLowerCase()} from the hierarchy. ERPNext checks linked records before deleting it.',
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: rename && (newName.isEmpty || newName == name)
                    ? null
                    : () => Navigator.pop(dialog, true),
                child: Text(rename ? 'Rename' : 'Delete'),
              ),
            ],
          ),
        );
      },
    );
    if (identical(_dialogToken, token)) {
      _dialogToken = null;
      _changeRoute = null;
      _dialogScope = null;
    }
    if (confirmed != true ||
        !mounted ||
        model != widget.model ||
        scope != model.scope) {
      return;
    }
    final changing = model.change(intent, newName: rename ? newName : null);
    setState(() {});
    try {
      final changed = await changing;
      if (!mounted ||
          model != widget.model ||
          scope != model.scope ||
          !changed) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rename ? 'Record renamed.' : 'Record deleted.')),
      );
    } catch (error) {
      if (mounted && model == widget.model && scope == model.scope) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && model == widget.model) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.protect(
    Scaffold(
      appBar: AppBar(
        title: WorkspaceRouteTitle(
          '${widget.type.name} hierarchy',
          mark: RecordIcon(recordSymbol(widget.type.name, tree: true)),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh hierarchy',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<NativeTreePage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return MessagePanel(
              title: 'COULD NOT LOAD HIERARCHY',
              message: snapshot.error.toString(),
              action: _reload,
            );
          }
          final result = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(result),
                const SizedBox(height: 16),
                _nodes(result),
                _pager(result),
              ],
            ),
          );
        },
      ),
    ),
    () async {
      _reload();
      await widget.model.result;
    },
  );
  Widget _node(NativeTreeNode row, NativeTreePage result) {
    final name = row.name;
    return Material(
      color: WorkspaceTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: Icon(
          row.expandable ? Icons.folder_outlined : Icons.description_outlined,
        ),
        title: Text(row.title),
        subtitle: Text(name),
        onTap: () => _browse(row),
        trailing: (result.canRename || result.canDelete) && row.modified != null
            ? PopupMenuButton<String>(
                tooltip: 'Actions for $name',
                enabled: !_changing,
                onSelected: (action) =>
                    action == 'open' ? _open(name: name) : _change(row, action),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: Text('Open record'),
                  ),
                  if (result.canRename)
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  if (result.canDelete)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            : IconButton(
                tooltip: 'Open $name',
                onPressed: () => _open(name: name),
                icon: const Icon(Icons.open_in_new, size: 20),
              ),
      ),
    );
  }

  Widget _pager(NativeTreePage result) => Row(
    children: [
      Text(
        result.nodes.isEmpty
            ? '0 records'
            : 'Showing ${_start + 1}–${_start + result.nodes.length}',
      ),
      const Spacer(),
      IconButton(
        tooltip: 'Previous page',
        onPressed: _start == 0
            ? null
            : () {
                _page(false);
              },
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: !result.hasMore
            ? null
            : () {
                _page(true);
              },
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Widget _heading(NativeTreePage result) => Row(
    children: [
      Expanded(
        child: Text(
          widget.parentTitle ??
              'Top-level ${widget.type.name.toLowerCase()} records',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      if (result.canCreate)
        FilledButton.icon(
          onPressed: () => _open(),
          icon: const Icon(Icons.add),
          label: Text(widget.parent == null ? 'New' : 'New child'),
        ),
    ],
  );
  Widget _nodes(NativeTreePage result) => Expanded(
    child: result.nodes.isEmpty
        ? const Center(child: Text('No accessible records in this group.'))
        : ListView.separated(
            itemCount: result.nodes.length,
            separatorBuilder: (_, i) => const SizedBox(height: 7),
            itemBuilder: (context, i) => _node(result.nodes[i], result),
          ),
  );
}
