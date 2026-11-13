import 'ui/record_icon.dart';
import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_models.dart';
import 'widgets.dart';

Future<void> showWorkspacePicker(
  BuildContext context,
  ValueChanged<ErpModule?> onSelect, {
  VoidCallback? onAll,
  Iterable<ErpModule> available = ErpModule.values,
}) {
  String query = '';
  return showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (c, setLocal) {
        final modules = available.where(
          (m) => '${m.label} ${m.doctype} ${m.description}'
              .toLowerCase()
              .contains(query),
        );
        final showOverview = 'business overview'.contains(query);
        return Dialog(
          backgroundColor: WorkspaceTheme.canvas,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const Expanded(child: Display('Workspaces', size: 29)),
                    IconButton(
                      tooltip: 'Close workspaces',
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search workspaces',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (s) =>
                      setLocal(() => query = s.trim().toLowerCase()),
                ),
                if (onAll != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        onAll();
                      },
                      icon: const Icon(Icons.apps, size: 18),
                      label: const Text('All modules and settings'),
                    ),
                  ),
                const SizedBox(height: 15),
                if (!showOverview && modules.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.search_off_outlined),
                    title: Text('No matching workspaces'),
                    subtitle: Text(
                      'Try a workspace or record name, such as Stock or Item.',
                    ),
                  ),
                if (showOverview)
                  ListTile(
                    leading: const Icon(Icons.space_dashboard_outlined),
                    title: const Text('Business overview'),
                    onTap: () {
                      Navigator.pop(c);
                      onSelect(null);
                    },
                  ),
                for (final m in modules)
                  ListTile(
                    leading: RecordIcon(
                      moduleIcon(m),
                      tone: moduleMark(m.label).$2,
                    ),
                    title: Text(m.label),
                    subtitle: Text(
                      m.description,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () {
                      Navigator.pop(c);
                      onSelect(m);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
