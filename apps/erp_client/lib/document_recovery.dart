import 'dart:math';

import 'erp_api.dart';
import 'native_models.dart';

/// Holds only a durable server reference. Financial draft payloads stay in memory.
class DocumentOperation {
  DocumentOperation(
    this.api,
    this.company,
    this.kind,
    this.doctype,
    this.name,
    this.action, {
    this.isCurrent,
  }) : account = api.account,
       requestId =
           'native-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  final ErpApi api;
  final bool Function()? isCurrent;
  final String company, kind, doctype, action, account, requestId;
  final String? name;
  NativeDocument? confirmed;
  bool _closed = false;

  bool get _sameAccount => api.account == account && api.accessReady;
  void _checkScope(int revision, {bool originating = false}) {
    if (!_sameAccount ||
        api.accessRevision != revision ||
        originating && !(isCurrent?.call() ?? true)) {
      throw const ErpException(
        'Access changed. Recheck the operation from Pending operations.',
        permissionDenied: true,
      );
    }
  }

  Future<NativeDocument> perform(
    Future<NativeDocument> Function(String requestId) write,
  ) async {
    final revision = api.accessRevision;
    _checkScope(revision, originating: true);
    // A failed preparation never sends the business write.
    await api.beginOperation(
      company,
      kind,
      requestId,
      doctype: doctype,
      name: name,
      action: action,
    );
    _checkScope(revision, originating: true);
    try {
      final result = await write(requestId);
      _checkScope(revision, originating: true);
      confirmed = result;
      return result;
    } catch (error) {
      if (!_sameAccount ||
          api.accessRevision != revision ||
          !(isCurrent?.call() ?? true)) {
        throw DocumentWriteUncertain(
          this,
          const ErpException(
            'Access changed before the result could be confirmed.',
          ),
        );
      }
      if (error is ErpException &&
          (error.validationRejected ||
              error.staleDocument ||
              error.permissionDenied ||
              error.sessionExpired)) {
        // A server rejection is editable. Unsealed references remain visible
        // in Pending operations if the separate closing request fails.
        try {
          final response = await reconcile(close: true);
          if (response['state'] == 'completed') return confirmed!;
          if (response['state'] == 'closed') {
            await api.acknowledgeOperation(company, requestId);
          }
        } catch (_) {}
        rethrow;
      }
      throw DocumentWriteUncertain(this, error);
    }
  }

  Future<Map<String, dynamic>> reconcile({bool close = false}) async {
    final revision = api.accessRevision;
    _checkScope(revision);
    final response = close
        ? await api.closeOperation(company, requestId)
        : await api.operationStatus(company, requestId);
    _checkScope(revision);
    _closed = response['state'] == 'closed';
    if (response['state'] == 'completed') {
      confirmed = NativeDocument.fromJson(objectMap(response['result']));
    }
    return response;
  }

  Future<void> acknowledge(NativeDocument? shown) async {
    if (!_sameAccount ||
        !(shown == null ? _closed : identical(confirmed, shown))) {
      return;
    }
    try {
      await api.acknowledgeOperation(company, requestId);
    } catch (_) {
      // Keep the server reference discoverable if acknowledgement is lost.
    }
  }
}

class DocumentWriteUncertain implements Exception {
  const DocumentWriteUncertain(this.operation, this.cause);
  final DocumentOperation operation;
  final Object cause;
  @override
  String toString() =>
      'The outcome is not confirmed. Check the original request before making another change. $cause';
}

class DocumentWriteUnverified implements Exception {
  const DocumentWriteUnverified(this.cause);
  final Object cause;
  @override
  String toString() =>
      'The outcome is not confirmed. Inspect the current server record before making another change. $cause';
}
