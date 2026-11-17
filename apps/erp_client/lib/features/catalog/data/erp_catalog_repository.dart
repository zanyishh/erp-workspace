import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/catalog_models.dart';
import 'catalog_repository.dart';
import 'master_import_repository.dart';
import 'native_tree_repository.dart';

class ErpCatalogRepository
    implements CatalogRepository, NativeTreeRepository, MasterImportRepository {
  ErpCatalogRepository({required this._api, this.company});
  final ErpApi _api;
  final String? company;
  @override
  Object get identity => (_api, _api.baseUri, _api.account, company);
  @override
  Object? get scope =>
      _api.accessReady ? (identity, _api.accessRevision) : null;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Future<T> _read<T>(Future<T> Function() read) async {
    final owner = scope;
    if (owner == null) {
      throw _changed;
    }
    final value = await read();
    if (owner != scope) {
      throw _changed;
    }
    return value;
  }

  @override
  Future<CatalogSnapshot> catalog() => _read(
    () async =>
        CatalogSnapshot.fromNative(await _api.nativeCatalog(company: company)),
  );
  @override
  Future<NativeRecordPage> records(
    String doctype, {
    String query = '',
    int start = 0,
  }) => _read(
    () async => NativeRecordPage.fromRows(
      await _api.nativeRecords(
        doctype,
        company: company,
        query: query,
        start: start,
      ),
    ),
  );
  @override
  Future<List<Map<String, dynamic>>> groups(
    String doctype,
    String groupType,
    String query,
  ) => _read(
    () async => List.unmodifiable(
      (await _api.searchLinks(
        groupType,
        query,
        parent: doctype,
        field: 'group',
        contextValues: const {},
      )).map((row) => Map<String, dynamic>.unmodifiable(row)),
    ),
  );
  @override
  Future<int> reclassify(
    String doctype,
    List<Map<String, String>> records,
    String group,
  ) => _read(() {
    final selectedCompany = company;
    if (selectedCompany == null) {
      throw const ErpException(
        'Choose a company before changing groups.',
        validationRejected: true,
      );
    }
    return _api.reclassifyMasters(doctype, selectedCompany, records, group);
  });
  @override
  Future<NativeTreePage> tree(
    String doctype, {
    String? parent,
    int start = 0,
  }) => _read(
    () async => NativeTreePage.fromJson(
      await _api.nativeTree(
        doctype,
        company: company,
        parent: parent,
        start: start,
      ),
    ),
  );
  @override
  Future<void> changeTree(
    String doctype,
    String name,
    String modified,
    String action, {
    String? newName,
  }) => _read(
    () => _api.changeTreeRecord(
      doctype,
      name,
      modified,
      action,
      company: company,
      newName: newName,
    ),
  );
  @override
  Future<MasterImportPreview> importMasters(
    String doctype,
    String stage, {
    String? content,
  }) => _read(
    () async => MasterImportPreview.fromJson(
      await _api.importMasters(
        doctype,
        company ??
            (throw const ErpException(
              'Choose a company before importing records.',
              validationRejected: true,
            )),
        stage,
        content: content,
      ),
    ),
  );
}
