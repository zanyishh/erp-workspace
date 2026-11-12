import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_models.dart';
import 'widgets.dart';

Future<void> showWorkspacePicker(
  BuildContext context,
  ValueChanged<ErpModule?> onSelect, {
  VoidCallback? onAll,
}) {
  String query = '';
  return showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (c, setLocal) => Dialog(
        backgroundColor: WorkspaceTheme.canvas,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 530),
          child: Padding(
            padding: const EdgeInsets.all(23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Display('FIND YOUR WORKSPACE', size: 29),
                    ),
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
                    hintText: 'Search modules…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (s) => setLocal(() => query = s.toLowerCase()),
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
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if ('business overview'.contains(query))
                          ListTile(
                            leading: const Icon(Icons.space_dashboard_outlined),
                            title: const Text('Business overview'),
                            onTap: () {
                              Navigator.pop(c);
                              onSelect(null);
                            },
                          ),
                        for (final m in ErpModule.values.where(
                          (m) => '${m.label} ${m.description}'
                              .toLowerCase()
                              .contains(query),
                        ))
                          ListTile(
                            leading: Icon(moduleIcon(m)),
                            title: Text(m.label),
                            subtitle: Text(
                              m.description,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: const Icon(Icons.arrow_outward, size: 16),
                            onTap: () {
                              Navigator.pop(c);
                              onSelect(m);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
