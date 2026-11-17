import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _search = TextEditingController();
  final _rows = <ErpModule?, GlobalKey>{
    for (final module in <ErpModule?>[null, ...ErpModule.values])
      module: GlobalKey(),
  };
  int _cursor = 0;
  bool _navigating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _choose(ErpModule? module) {
    Navigator.pop(context);
    widget.onSelect(module);
  }

  void _filter(String value) {
    setState(() {
      widget.model.search(value);
      _cursor = 0;
      _navigating = value.trim().isNotEmpty;
    });
  }

  void _move(List<ErpModule?> results, int direction) {
    if (results.isEmpty) return;
    setState(() {
      _cursor = (_cursor + direction).clamp(0, results.length - 1);
      _navigating = true;
    });
    final row = _rows[results[_cursor]]?.currentContext;
    if (row != null) Scrollable.ensureVisible(row, alignment: .5);
  }

  List<ErpModule?> get _results => <ErpModule?>[
    if (widget.model.showOverview) null,
    ...widget.model.modules,
  ];

  @override
  Widget build(BuildContext context) {
    final phone = workspaceUsesPhoneNavigation(context);
    final results = _results;
    final heading = Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: const Display('Workspaces', size: 32),
          ),
        ),
        IconButton(
          tooltip: 'Close workspaces',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
    final search = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(results, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(results, -1),
      },
      child: TextField(
        controller: _search,
        autofocus: !phone,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: 'Search workspaces',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    _filter('');
                  },
                ),
        ),
        onChanged: _filter,
        onSubmitted: (_) {
          final matches = _results;
          if (_cursor < matches.length) _choose(matches[_cursor]);
        },
      ),
    );
    final choices = <Widget>[
      if (results.isEmpty)
        const ListTile(
          leading: Icon(Icons.search_off_outlined),
          title: Text('No matching workspaces'),
          subtitle: Text(
            'Try a workspace or record name, such as Stock or Item.',
          ),
        ),
      for (final (i, module) in results.indexed)
        Padding(
          key: _rows[module],
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            selected: widget.selected == module,
            selectedColor: WorkspaceTheme.ink,
            selectedTileColor: _navigating && _cursor != i
                ? Colors.transparent
                : WorkspaceTheme.canvas,
            tileColor: _navigating && _cursor == i
                ? WorkspaceTheme.canvas
                : null,
            leading: RecordIcon(
              module == null
                  ? Icons.space_dashboard_outlined
                  : moduleIcon(module),
            ),
            title: Text(
              module?.label ?? 'Business overview',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: module == null
                ? null
                : Text(
                    module.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WorkspaceTheme.muted,
                    ),
                  ),
            trailing: Icon(
              widget.selected == module
                  ? Icons.check_rounded
                  : Icons.chevron_right,
              size: 18,
              color: WorkspaceTheme.muted,
            ),
            onTap: () => _choose(module),
          ),
        ),
      if (widget.onAll != null) ...[
        const Divider(height: 16),
        ListTile(
          title: const Text('All modules and settings'),
          leading: const RecordIcon(Icons.library_books_outlined),
          trailing: const Icon(Icons.chevron_right, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: () {
            Navigator.pop(context);
            widget.onAll!();
          },
        ),
      ],
    ];
    final body = SafeArea(
      child: Padding(
        padding: EdgeInsets.all(phone ? 16 : 20),
        child: LayoutBuilder(
          builder: (context, box) {
            final header = [
              heading,
              const SizedBox(height: 12),
              search,
              const SizedBox(height: 12),
            ];
            // Keep the search reachable when a landscape keyboard leaves only one row.
            if (box.maxHeight <
                285 * MediaQuery.textScalerOf(context).scale(14) / 14) {
              return ListView(children: [...header, ...choices]);
            }
            return Column(
              mainAxisSize: phone ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                Flexible(
                  child: ListView(shrinkWrap: !phone, children: choices),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (phone) {
      return Dialog.fullscreen(
        backgroundColor: WorkspaceTheme.light,
        child: body,
      );
    }
    return Dialog(
      backgroundColor: WorkspaceTheme.light,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530, maxHeight: 620),
        child: body,
      ),
    );
  }
}
