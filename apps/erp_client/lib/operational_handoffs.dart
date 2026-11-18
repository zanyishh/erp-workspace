import 'package:flutter/material.dart';

import 'erp_api.dart';
import 'native_models.dart';

class HandoffTarget {
  const HandoffTarget(this.type, {this.name, this.draft});
  final String type;
  final String? name;
  final NativeDocument? draft;
}

const operationalActions = {
  'Inspect receipt items',
  'Maintenance logs',
  'Maintenance plan',
};

Future<Map<String, dynamic>?> _pick(
  BuildContext context,
  String title,
  List<Map<String, dynamic>> rows,
  String Function(Map<String, dynamic>) label,
  String Function(Map<String, dynamic>) detail,
  String empty,
) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (dialog) => SimpleDialog(
    title: Text(title),
    children: [
      if (rows.isEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Text(empty)),
      for (final row in rows)
        ListTile(
          title: Text(label(row)),
          subtitle: Text(detail(row)),
          onTap: () => Navigator.pop(dialog, row),
        ),
      TextButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('Close'),
      ),
    ],
  ),
);

Future<HandoffTarget?> openOperationalAction(
  BuildContext context,
  ErpApi api,
  String action,
  String source,
) async {
  final revision = api.accessRevision;
  bool sameAccess() => revision == api.accessRevision && api.accessReady;
  if (action == 'Maintenance plan') {
    final result = await api.assetMaintenancePlan(source);
    if (!context.mounted || !sameAccess()) return null;
    final draft = result['draft'];
    return HandoffTarget(
      'Asset Maintenance',
      name: result['name'] as String?,
      draft: draft == null ? null : NativeDocument.fromJson(objectMap(draft)),
    );
  }
  if (action == 'Maintenance logs') {
    final result = await api.maintenanceLogs(source);
    if (!context.mounted || !sameAccess()) return null;
    final row = await _pick(
      context,
      'Maintenance logs',
      (result['logs'] as List).map(objectMap).toList(),
      (r) => '${r['task_name'] ?? r['name']} · ${r['maintenance_status']}',
      (r) => 'Due ${r['due_date']} · ${r['name']}',
      'No maintenance logs for this plan.',
    );
    return row == null || !context.mounted || !sameAccess()
        ? null
        : HandoffTarget('Asset Maintenance Log', name: row['name'] as String);
  }
  final result = await api.receiptInspectionItems(source);
  if (!context.mounted || !sameAccess()) return null;
  final row = await _pick(
    context,
    'Inspect receipt items',
    (result['rows'] as List).map(objectMap).toList(),
    (r) => 'Row ${r['index']} · ${r['item']}',
    (r) => r['inspection']?.toString() ?? 'Received quantity ${r['quantity']}',
    'No items on this receipt are available for inspection.',
  );
  if (row == null || !context.mounted || !sameAccess()) return null;
  final existing = row['inspection'] as String?;
  if (existing != null && existing.isNotEmpty) {
    return HandoffTarget('Quality Inspection', name: existing);
  }
  String text = '';
  final sample = await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (c, update) {
        final value = double.tryParse(text);
        final valid =
            value != null &&
            value.isFinite &&
            value > 0 &&
            value <= double.parse(row['quantity'] as String);
        return AlertDialog(
          title: const Text('Create incoming inspection'),
          content: TextField(
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Sample size',
              helperText: 'Received ${row['quantity']} · ${row['item']}',
            ),
            onChanged: (v) => update(() => text = v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(dialog, text) : null,
              child: const Text('Create draft'),
            ),
          ],
        );
      },
    ),
  );
  if (sample == null || !context.mounted || !sameAccess()) return null;
  final created = await api.inspectReceipt(
    source,
    row['row'] as String,
    sample,
    result['modified'] as String,
  );
  return !context.mounted || !sameAccess()
      ? null
      : HandoffTarget('Quality Inspection', name: created['name'] as String);
}
