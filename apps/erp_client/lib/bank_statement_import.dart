import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'erp_api.dart';
import 'document_dialogs.dart';
import 'ui/access_gate.dart';

class BankStatementImport extends StatefulWidget {
  const BankStatementImport({
    super.key,
    required this.api,
    required this.company,
    required this.bank,
    this.pickFile,
  });
  final ErpApi api;
  final String company, bank;
  final Future<XFile?> Function()? pickFile;
  @override
  State<BankStatementImport> createState() => _BankImportState();
}

class _BankImportState extends State<BankStatementImport> {
  static const fields = {
    'date': 'Transaction date',
    'deposit': 'Deposit / credit',
    'withdrawal': 'Withdrawal / debit',
    'reference': 'Bank reference',
    'description': 'Narration / description',
    'id': 'Unique bank transaction ID',
  };
  String format = 'YMD', content = '', filename = '';
  List<String> headers = [];
  Map<String, String> mapping = {};
  Map<String, dynamic>? preview, receipt;
  String? error;
  bool busy = false, uncertain = false, mappingChanged = false;
  int operation = 0, contextVersion = 0;
  DialogRoute<bool>? leaveRoute;
  Object get scope => (
    widget.api,
    widget.api.account,
    widget.company,
    widget.bank,
    widget.api.accessRevision,
    contextVersion,
  );
  bool current(Object value) =>
      mounted && value == scope && widget.api.accessReady;
  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(accessChanged);
  }

  void accessChanged() {
    contextVersion++;
    dismissDocumentDialog(leaveRoute);
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(accessChanged);
    dismissDocumentDialog(leaveRoute);
    super.dispose();
  }

  @override
  void didUpdateWidget(BankStatementImport old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api ||
        old.company != widget.company ||
        old.bank != widget.bank) {
      old.api.removeAccessListener(accessChanged);
      widget.api.addAccessListener(accessChanged);
      dismissDocumentDialog(leaveRoute);
      content = filename = '';
      headers = [];
      mapping = {};
      preview = receipt = null;
      error = null;
      operation++;
      contextVersion++;
      busy = uncertain = mappingChanged = false;
    }
  }

  Future<void> leave() async {
    if (busy || leaveRoute != null) return;
    if (receipt != null || !mappingChanged && !uncertain) {
      Navigator.pop(context, receipt != null);
      return;
    }
    final captured = scope;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Keep your import setup?'),
        content: Text(
          uncertain
              ? 'The outcome is not confirmed. Keep the original CSV and mapping so its existing statement lines can be checked before another import.'
              : 'Your column mapping and date format changes have not been imported.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Leave import'),
          ),
        ],
      ),
    );
    leaveRoute = route;
    final discard = await Navigator.of(context).push(route);
    leaveRoute = null;
    if (discard == true && mounted && current(captured)) Navigator.pop(context);
  }

  Future<void> act(Future<void> Function() op) async {
    if (busy) return;
    final rev = scope;
    final sequence = ++operation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await op();
    } catch (e) {
      if (current(rev)) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && sequence == operation) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>> call(String stage) => widget.api.importBankCsv(
    widget.company,
    widget.bank,
    stage,
    content,
    mapping,
    format,
  );

  Future<void> choose() => act(() async {
    final rev = scope;
    final file =
        await (widget.pickFile?.call() ??
            openFile(
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: 'CSV',
                  extensions: ['csv'],
                  mimeTypes: ['text/csv', 'application/csv'],
                  uniformTypeIdentifiers: [
                    'public.comma-separated-values-text',
                  ],
                ),
              ],
            ));
    if (file == null || !current(rev)) return;
    setState(() {
      filename = file.name;
      preview = receipt = null;
      headers = [];
      mapping = {};
      content = '';
      mappingChanged = uncertain = false;
    });
    if (await file.length() > 262144) {
      throw const FormatException('Choose a UTF-8 CSV file up to 256 KB.');
    }
    final value = utf8.decode(await file.readAsBytes());
    if (!current(rev)) return;
    content = value;
    final result = await call('columns');
    if (!current(rev)) return;
    setState(() {
      headers = List<String>.from(result['headers']);
      mapping = Map<String, String>.from(result['mapping']);
    });
  });

  Future<void> review() => act(() async {
    final rev = scope;
    final result = await call('preview');
    if (current(rev)) {
      setState(() => preview = result);
    }
  });

  Future<void> post() => act(() async {
    final rev = scope;
    try {
      final result = await call('import');
      if (current(rev)) {
        setState(() {
          receipt = result;
          preview = null;
          uncertain = mappingChanged = false;
        });
      }
    } catch (failure) {
      if (current(rev) &&
          !(failure is ErpException &&
              (failure.validationRejected ||
                  failure.permissionDenied ||
                  failure.sessionExpired))) {
        setState(() => uncertain = true);
      }
      rethrow;
    }
  });

  Future<void> checkImport() => act(() async {
    final rev = scope;
    final result = await call('preview');
    if (!current(rev)) return;
    setState(() {
      preview = result;
      if (result['new_count'] == 0) {
        receipt = {'verified': true, 'duplicates': result['duplicates']};
        preview = null;
        uncertain = mappingChanged = false;
      } else {
        error = 'Some lines are not present yet. Check again or retry this same import; existing lines are skipped.';
      }
    });
  });

  void changed(void Function() mutation) => setState(() {
    mutation();
    mappingChanged = true;
    preview = receipt = null;
    error = null;
  });

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      await widget.api.bankStatements(widget.company, widget.bank, '');
      if (mounted) {
        setState(() {
          content = '';
          filename = '';
          headers = [];
          mapping = {};
          preview = receipt = null;
          error = null;
          uncertain = mappingChanged = false;
        });
      }
    },
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Import bank statement')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.bank,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(widget.company),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy || uncertain ? null : choose,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      filename.isEmpty
                          ? 'Choose CSV file'
                          : 'Choose another CSV file',
                    ),
                  ),
                  if (filename.isNotEmpty) Text(filename),
                  if (busy) const LinearProgressIndicator(),
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
                  if (uncertain) ...[
                    const Text(
                      'Import outcome not confirmed. Keep this file and mapping unchanged while checking.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: busy ? null : checkImport,
                          child: const Text('Check import outcome'),
                        ),
                        TextButton(
                          onPressed: busy ? null : post,
                          child: const Text('Retry same import'),
                        ),
                      ],
                    ),
                  ],
                  if (receipt != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        receipt!['verified'] == true
                            ? "All statement lines are present. Verified ${receipt!['duplicates']} existing lines."
                            : "Imported ${receipt!['created']} statement ${receipt!['created'] == 1 ? 'line' : 'lines'}. Skipped ${receipt!['duplicates']} duplicates.",
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Return to bank matching'),
                    ),
                  ] else if (headers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final entry in fields.entries)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          '${entry.key}-$filename-${headers.hashCode}',
                        ),
                        isExpanded: true,
                        initialValue: mapping[entry.key] ?? '',
                        decoration: InputDecoration(labelText: entry.value),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Unmapped'),
                          ),
                          for (final h in headers)
                            DropdownMenuItem(
                              value: h,
                              child: Text(h, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: busy || uncertain
                            ? null
                            : (v) => changed(() {
                                if (v == null || v.isEmpty) {
                                  mapping.remove(entry.key);
                                } else {
                                  mapping[entry.key] = v;
                                }
                              }),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: format,
                      decoration: const InputDecoration(
                        labelText: 'Date format',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'YMD',
                          child: Text('YYYY-MM-DD'),
                        ),
                        DropdownMenuItem(
                          value: 'DMY',
                          child: Text('DD/MM/YYYY'),
                        ),
                        DropdownMenuItem(
                          value: 'MDY',
                          child: Text('MM/DD/YYYY'),
                        ),
                      ],
                      onChanged: busy || uncertain
                          ? null
                          : (v) => changed(() => format = v!),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy || uncertain ? null : review,
                      child: const Text('Preview statement lines'),
                    ),
                    if (preview != null) ...[
                      Text(
                        "${preview!['new_count']} new · ${preview!['duplicates']} duplicates · ${preview!['currency']}",
                      ),
                      for (final row in preview!['rows'] as List)
                        ListTile(
                          title: Text(
                            "Line ${row['line']} · ${row['date']} · ${double.parse(row['deposit']) > 0 ? 'Deposit ${row['deposit']}' : 'Withdrawal ${row['withdrawal']}'}",
                          ),
                          subtitle: Text(
                            [
                              row['reference_number'],
                              row['description'],
                              if (row['existing'] != null)
                                'Duplicate · ${row['existing']}',
                            ].where((v) => v != null && v != '').join(' · '),
                          ),
                        ),
                      if (!uncertain && (preview!['new_count'] as num) > 0)
                        FilledButton(
                          onPressed: busy ? null : post,
                          child: Text(
                            "Import ${preview!['new_count']} statement ${preview!['new_count'] == 1 ? 'line' : 'lines'}",
                          ),
                        ),
                    ],
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
