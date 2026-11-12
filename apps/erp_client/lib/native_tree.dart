import 'package:flutter/material.dart';
import 'design.dart';
import 'document_editor.dart';
import 'erp_api.dart';
import 'native_models.dart';
import 'widgets.dart';

class NativeTreeScreen extends StatefulWidget {
  const NativeTreeScreen({
    super.key,
    required this.api,
    required this.type,
    this.company,
    this.parent,
    this.parentTitle,
  });
  final ErpApi api;
  final NativeType type;
  final String? company, parent, parentTitle;
  @override
  State<NativeTreeScreen> createState() => _NativeTreeScreenState();
}

class _NativeTreeScreenState extends State<NativeTreeScreen> {
  int _start = 0;
  late Future<Map<String, dynamic>> _future = _load();
  Future<Map<String, dynamic>> _load() => widget.api.nativeTree(
    widget.type.name,
    parent: widget.parent,
    company: widget.company,
    start: _start,
  );
  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _open({String? name}) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: widget.api,
          doctype: widget.type.name,
          name: name,
          company: widget.company,
          treeParent: name == null ? widget.parent : null,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _browse(Map<String, dynamic> row) async {
    if (!enabled(row['expandable'])) {
      await _open(name: row['name'] as String);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NativeTreeScreen(
          api: widget.api,
          type: widget.type,
          company: widget.company,
          parent: row['name'] as String,
          parentTitle: row['title'] as String,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Display('${widget.type.name.toUpperCase()} · HIERARCHY', size: 25),
      actions: [
        IconButton(
          tooltip: 'Refresh hierarchy',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
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
        final rows = (result['nodes'] as List).map(objectMap).toList();
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.parentTitle ??
                          'Top-level ${widget.type.name.toLowerCase()} records',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (enabled(result['can_create']))
                    FilledButton.icon(
                      onPressed: () => _open(),
                      icon: const Icon(Icons.add),
                      label: Text(widget.parent == null ? 'New' : 'New child'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No accessible records in this group.'),
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, i) => const SizedBox(height: 7),
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          final name = row['name'] as String;
                          return Material(
                            color: WorkspaceTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              leading: Icon(
                                enabled(row['expandable'])
                                    ? Icons.folder_outlined
                                    : Icons.description_outlined,
                              ),
                              title: Text(row['title'] as String),
                              subtitle: Text(name),
                              onTap: () => _browse(row),
                              trailing: IconButton(
                                tooltip: 'Open $name',
                                onPressed: () => _open(name: name),
                                icon: const Icon(Icons.open_in_new, size: 20),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Row(
                children: [
                  Text(
                    rows.isEmpty
                        ? '0 records'
                        : 'Showing ${_start + 1}–${_start + rows.length}',
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _start == 0
                        ? null
                        : () {
                            _start = (_start - 50).clamp(0, _start);
                            _reload();
                          },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: !enabled(result['has_more'])
                        ? null
                        : () {
                            _start += 50;
                            _reload();
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
