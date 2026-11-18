import 'package:flutter/material.dart';

import '../../core/models/erp_models.dart';
import '../../features/workspace/presentation/workspace_picker_view.dart';
import '../../features/workspace/presentation/workspace_picker_view_model.dart';

Future<void> showWorkspacePicker(
  BuildContext context,
  ValueChanged<ErpModule?> onSelect, {
  VoidCallback? onAll,
  ErpModule? selected,
  Iterable<ErpModule> available = ErpModule.values,
}) {
  final model = WorkspacePickerViewModel(available);
  return showDialog<void>(
    context: context,
    builder: (_) => WorkspacePickerView(
      model: model,
      onSelect: onSelect,
      onAll: onAll,
      selected: selected,
    ),
  );
}
