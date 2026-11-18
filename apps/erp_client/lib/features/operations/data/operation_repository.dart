import '../models/operation_reference.dart';

abstract class OperationRepository {
  /// Opaque cache owner; null means access is awaiting revalidation.
  Object? get scope;
  Future<OperationPage> load({int start = 0});
  Future<OperationReference> status(String requestId);
  Future<OperationReference> closeUnposted(String requestId);
  Future<void> acknowledge(String requestId);
}
