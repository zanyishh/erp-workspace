import '../models/authentication.dart';

abstract class OnboardingRepository {
  Future<void> registerOwner(SignInValues values, {required String industry});
  Future<void> joinNew(SignInValues values);
  Future<void> joinExisting(SignInValues values);
}
