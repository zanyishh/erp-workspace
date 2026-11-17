import '../models/catalog_models.dart';
import 'catalog_repository.dart';

abstract interface class NativeTreeRepository implements CatalogSource {
  Future<NativeTreePage> tree(String doctype, {String? parent, int start = 0});
  Future<void> changeTree(
    String doctype,
    String name,
    String modified,
    String action, {
    String? newName,
  });
}
