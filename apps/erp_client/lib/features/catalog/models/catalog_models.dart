import '../../../core/models/json_values.dart';
import '../../../core/models/native_models.dart';

Map<String, dynamic> _frozenMap(Map<String, dynamic> value) =>
    immutableJsonMap(value);

class CatalogSnapshot {
  CatalogSnapshot.fromNative(NativeCatalog value)
    : site = value.site,
      types = List.unmodifiable(value.types),
      reports = List.unmodifiable(value.reports.map(_frozenMap));
  final String site;
  final List<NativeType> types;
  final List<Map<String, dynamic>> reports;
}

class NativeRecordPage {
  NativeRecordPage.fromRows(List<Map<String, dynamic>> values)
    : rows = List.unmodifiable(
        values.map((value) {
          if (value['name'] is! String || (value['name'] as String).isEmpty) {
            throw const FormatException('A native record has no identifier.');
          }
          return _frozenMap(value);
        }),
      );
  final List<Map<String, dynamic>> rows;
  bool get hasMore => rows.length == 50;
}

class NativeTreeNode {
  NativeTreeNode.fromJson(Map<String, dynamic> value)
    : name = value['name'] as String,
      title = value['title'] as String,
      modified = value['modified'] as String?,
      expandable = enabled(value['expandable']);
  final String name, title;
  final String? modified;
  final bool expandable;
}

class NativeTreePage {
  NativeTreePage.fromJson(Map<String, dynamic> value)
    : nodes = List.unmodifiable(
        (value['nodes'] as List).map(
          (node) => NativeTreeNode.fromJson(objectMap(node)),
        ),
      ),
      hasMore = enabled(value['has_more']),
      canCreate = enabled(value['can_create']),
      canRename = enabled(value['can_rename']),
      canDelete = enabled(value['can_delete']);
  final List<NativeTreeNode> nodes;
  final bool hasMore, canCreate, canRename, canDelete;
}

class MasterImportPreview {
  MasterImportPreview.fromJson(Map<String, dynamic> value)
    : data = _frozenMap(value);
  final Map<String, dynamic> data;
  int get count => data['count'] as int? ?? 0;
  bool get alreadyImported => data['already_imported'] == true;
  List<Object?> get errors =>
      (data['errors'] as List?)?.cast<Object?>() ?? const [];
  List<Object?> get columns =>
      (data['columns'] as List?)?.cast<Object?>() ?? const [];
}

const masterImportMaxBytes = 262144;

class ImportFile {
  ImportFile(this.name, List<int> bytes) : bytes = List.unmodifiable(bytes);
  final String name;
  final List<int> bytes;
}
