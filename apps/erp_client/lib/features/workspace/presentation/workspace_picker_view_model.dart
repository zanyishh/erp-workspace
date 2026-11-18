import '../../../core/models/erp_models.dart';

class WorkspacePickerViewModel {
  WorkspacePickerViewModel(Iterable<ErpModule> available)
    : _available = List.unmodifiable(available);
  final List<ErpModule> _available;
  String _query = '';
  void search(String value) {
    _query = value.trim().toLowerCase();
  }

  bool get showOverview => 'business overview'.contains(_query);
  List<ErpModule> get modules => List.unmodifiable(
    _available.where(
      (module) => '${module.label} ${module.doctype} ${module.description}'
          .toLowerCase()
          .contains(_query),
    ),
  );
}
