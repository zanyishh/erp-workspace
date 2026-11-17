import '../../../erp_api.dart' show ErpApi;
import '../models/authentication.dart';
import 'onboarding_repository.dart';

class ErpOnboardingRepository implements OnboardingRepository {
  ErpOnboardingRepository({
    required this._connect,
    required this._authenticate,
  });
  final ErpApi Function() _connect;
  final Future<void> Function(ErpApi, String, String) _authenticate;
  Future<void> _temporary(Future<void> Function(ErpApi) command) async {
    final api = _connect();
    try {
      await command(api);
    } finally {
      api.close();
    }
  }

  @override
  Future<void> registerOwner(SignInValues values, {required String industry}) =>
      _temporary(
        (api) => api.registerOwner(
          fullName: values.fullName.trim(),
          email: values.username.trim(),
          password: values.password,
          company: values.company.trim(),
          industry: industry,
        ),
      );
  @override
  Future<void> joinNew(SignInValues values) => _temporary(
    (api) => api.acceptInvitation(
      values.invitation.trim(),
      fullName: values.fullName.trim(),
      email: values.username.trim(),
      password: values.password,
    ),
  );
  @override
  Future<void> joinExisting(SignInValues values) => _temporary(
    (api) => api.redeemExistingInvitation(
      values.invitation.trim(),
      () => _authenticate(api, values.username.trim(), values.password),
    ),
  );
}
