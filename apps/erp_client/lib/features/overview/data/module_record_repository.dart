import '../../../core/models/erp_models.dart';

typedef RecordLoader = Future<List<ErpRecord>> Function(
  String query,
  int start,
);

abstract interface class ModuleRecordRepository {
  Future<List<ErpRecord>> load(String query, int start);
}

/// Adapts the existing public loader callback at the composition boundary.
class CallbackModuleRecordRepository implements ModuleRecordRepository {
  CallbackModuleRecordRepository(this._load);
  final RecordLoader _load;
  @override
  Future<List<ErpRecord>> load(String query, int start) async =>
      List.unmodifiable(await _load(query, start));
}
