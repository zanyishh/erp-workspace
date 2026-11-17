import 'package:flutter/material.dart';

import '../../../core/models/erp_models.dart';
import '../../../core/ui/design.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/ui/record_icon.dart';
import 'workspace_picker_view_model.dart';

class WorkspacePickerView extends StatefulWidget {
  const WorkspacePickerView({
    super.key,
    required this.model,
    required this.onSelect,
    this.onAll,
    this.selected,
  });
  final WorkspacePickerViewModel model;
  final ValueChanged<ErpModule?> onSelect;
  final VoidCallback? onAll;
  final ErpModule? selected;
  @override
  State<WorkspacePickerView> createState() => _WorkspacePickerViewState();
}

class _WorkspacePickerViewState extends State<WorkspacePickerView> {
  @override
  Widget build(BuildContext context) {
    final modules = widget.model.modules;
    final showOverview = widget.model.showOverview;
    final phone = workspaceUsesPhoneNavigation(context);
    final list = ListView(
      shrinkWrap: !phone,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(child: Display('Workspaces', size: 29)),
            IconButton(
              tooltip: 'Close workspaces',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 17),
        TextField(
          autofocus: !phone,
          decoration: const InputDecoration(
            labelText: 'Search workspaces',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (s) => setState(() => widget.model.search(s)),
        ),
        if (widget.onAll != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onAll!();
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
            selected: widget.selected == null,
            trailing: widget.selected == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () {
              Navigator.pop(context);
              widget.onSelect(null);
            },
          ),
        for (final m in modules)
          ListTile(
            leading: RecordIcon(moduleIcon(m), tone: moduleMark(m.label).$2),
            title: Text(m.label),
            subtitle: Text(m.description, style: const TextStyle(fontSize: 11)),
            selected: widget.selected == m,
            trailing: Icon(
              widget.selected == m ? Icons.check_rounded : Icons.chevron_right,
              size: 18,
            ),
            onTap: () {
              Navigator.pop(context);
              widget.onSelect(m);
            },
          ),
      ],
    );
    if (phone) {
      return Dialog.fullscreen(
        backgroundColor: WorkspaceTheme.canvas,
        child: list,
      );
    }
    return Dialog(
      backgroundColor: WorkspaceTheme.canvas,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: list,
      ),
    );
  }
}
