import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import '../models/operation_reference.dart';
import 'operation_repository.dart';

class ErpOperationRepository implements OperationRepository {
  ErpOperationRepository({required this._api, required this.company});
  final ErpApi _api;
  final String company;
  @override
  Object? get scope => _api.accessReady
      ? (_api, _api.baseUri, _api.account, company, _api.accessRevision)
      : null;
  static const _invalid = ErpException(
    'ERPNext returned an invalid operation response. Refresh and try again.',
  );
  static const _accessChanged = ErpException(
    'Access changed. Reload pending operations before continuing.',
    permissionDenied: true,
  );

  Future<T> _scoped<T>(Future<T> Function() read) async {
    final owner = scope;
    if (owner == null) throw _accessChanged;
    final result = await read();
    if (owner != scope) throw _accessChanged;
    return result;
  }

  OperationReference _reference(Map<String, dynamic> json, String id) {
    try {
      final value = OperationReference.fromJson(json);
      if (value.company != company || value.requestId != id) {
        throw const FormatException('Unexpected operation scope.');
      }
      return value;
    } on FormatException {
      throw _invalid;
    }
  }

  @override
  Future<OperationPage> load({int start = 0}) async {
    final json = await _scoped(
      () => _api.pendingOperations(company, start: start),
    );
    try {
      final page = OperationPage.fromJson(json);
      if (page.rows.any((row) => row.company != company)) {
        throw const FormatException('Unexpected operation company.');
      }
      return page;
    } on FormatException {
      throw _invalid;
    }
  }

  @override
  Future<OperationReference> status(String requestId) async => _reference(
    await _scoped(() => _api.operationStatus(company, requestId)),
    requestId,
  );
  @override
  Future<OperationReference> closeUnposted(String requestId) async =>
      _reference(
        await _scoped(() => _api.closeOperation(company, requestId)),
        requestId,
      );
  @override
  Future<void> acknowledge(String requestId) =>
      _scoped(() => _api.acknowledgeOperation(company, requestId));
}
