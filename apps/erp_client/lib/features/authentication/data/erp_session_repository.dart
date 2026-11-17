import '../../../core/models/erp_exception.dart';
import '../../../erp_api.dart' show ErpApi;
import 'session_repository.dart';

class ErpSessionRepository implements SessionRepository {
  ErpSessionRepository(this._api);
  final ErpApi _api;
  @override
  String get account => _api.account;
  @override
  Object get identity => (_api, _api.baseUri);
  @override
  Future<LoginVerification?> signIn(String username, String password) async {
    try {
      await _api.login(username, password);
      return null;
    } on LoginVerification catch (challenge) {
      return challenge;
    }
  }

  @override
  Future<void> verify(
    String username,
    LoginVerification challenge,
    String code,
  ) => _api.verifyLogin(username, challenge, code);
}
