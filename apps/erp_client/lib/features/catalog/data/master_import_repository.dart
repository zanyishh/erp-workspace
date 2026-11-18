import '../models/catalog_models.dart';
import 'catalog_repository.dart';

abstract interface class MasterImportRepository implements CatalogSource {
  Future<MasterImportPreview> importMasters(
    String doctype,
    String stage, {
    String? content,
  });
}
