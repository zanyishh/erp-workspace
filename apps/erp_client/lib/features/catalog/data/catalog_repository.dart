import '../models/catalog_models.dart';

abstract interface class CatalogSource {
  Object get identity;
  Object? get scope;
}

abstract interface class CatalogRepository implements CatalogSource {
  Future<CatalogSnapshot> catalog();
  Future<NativeRecordPage> records(
    String doctype, {
    String query = '',
    int start = 0,
  });
  Future<List<Map<String, dynamic>>> groups(
    String doctype,
    String groupType,
    String query,
  );
  Future<int> reclassify(
    String doctype,
    List<Map<String, String>> records,
    String group,
  );
}
