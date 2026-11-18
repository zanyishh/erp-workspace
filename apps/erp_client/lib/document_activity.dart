import 'ui/workspace_art.dart';
import 'ui/access_gate.dart';

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'erp_api.dart';
import 'file_actions.dart';
import 'invoice_preview.dart';
import 'native_models.dart';
import 'native_reports.dart';
import 'widgets.dart';

class DocumentActivityScreen extends StatefulWidget {
  const DocumentActivityScreen({
    super.key,
    required this.api,
    required this.type,
    required this.name,
    this.company,
  });
  final ErpApi api;
  final String type, name;
  final String? company;
  @override
  State<DocumentActivityScreen> createState() => _DocumentActivityScreenState();
}

class _DocumentActivityScreenState extends State<DocumentActivityScreen> {
  late Future<Map<String, dynamic>> _future = widget.api.documentActivity(
    widget.type,
    widget.name,
  );
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;
  void _reload() => setState(() {
    _future = widget.api.documentActivity(widget.type, widget.name);
  });
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _act(
    Future<void> Function() operation, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted && reload) _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final file = await openFile();
    if (file == null) return;
    if (await file.length() > 5000000) {
      throw const ErpException('Choose a file smaller than 5 MB.');
    }
    await widget.api.uploadAttachment(
      widget.type,
      widget.name,
      file.name,
      await file.readAsBytes(),
    );
  }

  Future<void> _assign() async {
    String? selected;
    var query = '';
    var future = widget.api.searchLinks('User', '');
    selected = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Assign this document'),
          content: SizedBox(
            width: 430,
            height: 380,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Search users'),
                  onChanged: (value) => update(() {
                    query = value;
                    future = widget.api.searchLinks('User', query);
                  }),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: future,
                    builder: (c, state) {
                      if (state.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.hasError) {
                        return MessagePanel(
                          title: 'Could not load users',
                          message: state.error.toString(),
                          action: () => update(() {
                            future = widget.api.searchLinks('User', query);
                          }),
                        );
                      }
                      if (state.data!.isEmpty) {
                        return const Center(child: Text('No matching users.'));
                      }
                      return ListView(
                        children: [
                          for (final user in state.data!)
                            ListTile(
                              title: Text(user['value'].toString()),
                              onTap: () => Navigator.pop(c, user['value']),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await widget.api.assignDocument(widget.type, widget.name, selected);
    }
  }

  Future<void> _print() async {
    if (widget.type == 'Sales Invoice' && widget.company != null) {
      final useDesign = await showDialog<bool>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Print invoice'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Invoice templates'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ERPNext print formats'),
            ),
          ],
        ),
      );
      if (useDesign == null || !mounted) return;
      if (useDesign) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => InvoicePreviewScreen(
              api: widget.api,
              company: widget.company!,
              invoice: widget.name,
            ),
          ),
        );
        return;
      }
    }
    final formats = await widget.api.printOptions(widget.type, widget.name);
    if (!mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Choose print format'),
        children: [
          for (final format in formats)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, format),
              child: Text(format),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    final file = await widget.api.printPdf(widget.type, widget.name, chosen);
    if (mounted) {
      await previewFile(context, file.name, file.bytes, api: widget.api);
    }
  }

  Future<void> _remove(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this attachment?'),
        content: const Text('The file will be removed from this ERP document.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep file'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.api.removeAttachment(widget.type, widget.name, id);
    }
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      final fresh = widget.api.documentActivity(widget.type, widget.name);
      setState(() {
        _future = fresh;
      });
      await fresh;
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Document activity'),
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, state) {
          if (state.hasError) {
            return MessagePanel(
              title: 'COULD NOT LOAD ACTIVITY',
              message: state.error.toString(),
              action: _reload,
            );
          }
          if (!state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = state.data!;
          final permissions = objectMap(data['permissions']);
          final attachments = (data['attachments'] as List).map(objectMap);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.type} · ${widget.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_error!),
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (enabled(permissions['write']))
                          TextButton.icon(
                            onPressed: _busy ? null : () => _act(_upload),
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach private file'),
                          ),
                        if (enabled(permissions['print']))
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _act(_print, reload: false),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print / PDF'),
                          ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _act(_assign),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Assign'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Panel(
                      border: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ColumnCaption('Files', icon: Icons.attach_file),
                          if (attachments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No attached files.'),
                            ),
                          for (final file in attachments)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                enabled(file['is_private'])
                                    ? Icons.lock_outline
                                    : Icons.insert_drive_file_outlined,
                              ),
                              title: Text(file['file_name'].toString()),
                              subtitle: Text('${file['file_size'] ?? 0} bytes'),
                              onTap: _busy
                                  ? null
                                  : () => _act(() async {
                                      final result = await widget.api
                                          .attachment(
                                            widget.type,
                                            widget.name,
                                            file['name'] as String,
                                          );
                                      if (context.mounted) {
                                        await previewFile(
                                          context,
                                          result.name,
                                          result.bytes,
                                          api: widget.api,
                                        );
                                      }
                                    }, reload: false),
                              trailing:
                                  enabled(permissions['write']) &&
                                      (file['attached_to_field'] ?? '')
                                          .toString()
                                          .isEmpty
                                  ? IconButton(
                                      tooltip: 'Remove ${file['file_name']}',
                                      onPressed: _busy
                                          ? null
                                          : () => _act(
                                              () => _remove(
                                                file['name'] as String,
                                              ),
                                            ),
                                      icon: const Icon(Icons.delete_outline),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Panel(
                      border: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ColumnCaption(
                            'Assigned to',
                            icon: Icons.people_outline,
                          ),
                          if ((data['assignments'] as List).isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No assignments.'),
                            ),
                          for (final user in (data['assignments'] as List).map(
                            objectMap,
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(user['owner'].toString()),
                              trailing: IconButton(
                                tooltip:
                                    'Remove assignment for ${user['owner']}',
                                onPressed: _busy
                                    ? null
                                    : () => _act(
                                        () => widget.api.unassignDocument(
                                          widget.type,
                                          widget.name,
                                          user['owner'] as String,
                                        ),
                                      ),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Panel(
                      border: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ColumnCaption(
                            'Comments & history',
                            icon: Icons.history,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _comment,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 10000,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Write a comment',
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _comment,
                              builder: (_, value, _) => TextButton(
                                onPressed: _busy || value.text.trim().isEmpty
                                    ? null
                                    : () => _act(() async {
                                        await widget.api.comment(
                                          widget.type,
                                          widget.name,
                                          value.text.trim(),
                                        );
                                        if (mounted) _comment.clear();
                                      }),
                                child: const Text('Add comment'),
                              ),
                            ),
                          ),
                          for (final comment in (data['comments'] as List).map(
                            objectMap,
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: SelectableText(
                                plainReportText(comment['content']),
                              ),
                              subtitle: Text(
                                '${comment['comment_type']} · ${comment['owner']} · ${comment['creation']}',
                              ),
                            ),
                          for (final version in (data['versions'] as List).map(
                            objectMap,
                          ))
                            ExpansionTile(
                              expansionAnimationStyle:
                                  MediaQuery.disableAnimationsOf(context)
                                  ? AnimationStyle.noAnimation
                                  : const AnimationStyle(
                                      duration: Duration(milliseconds: 180),
                                      curve: Curves.easeOutCubic,
                                    ),
                              tilePadding: EdgeInsets.zero,
                              title: Text('Edited by ${version['owner']}'),
                              subtitle: Text(version['creation'].toString()),
                              children: [
                                for (final change in version['changed'] as List)
                                  ListTile(
                                    title: Text(change[0].toString()),
                                    subtitle: SelectableText(
                                      '${jsonEncode(change[1])} → ${jsonEncode(change[2])}',
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
