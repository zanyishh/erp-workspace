import '../../../core/models/erp_exception.dart';

abstract class SessionRepository {
  String get account;
  Object get identity;
  Future<LoginVerification?> signIn(String username, String password);
  Future<void> verify(
    String username,
    LoginVerification challenge,
    String code,
  );
}
