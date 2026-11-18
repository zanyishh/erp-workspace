import '../../../core/models/email_address.dart';
import '../data/onboarding_repository.dart';
import '../models/authentication.dart';

class SignInViewModel {
  SignInViewModel(
    this._repository, {
    required this._signIn,
    this._entry = SignInEntry.signIn,
    this.industry = 'general',
    this._existingAccount = false,
  });
  final OnboardingRepository _repository;
  final Future<void> Function(String, String) _signIn;
  SignInEntry _entry;
  String industry;
  bool _existingAccount, _busy = false, _disposed = false;
  int _generation = 0;
  String? _error;
  SignInEntry get entry => _entry;
  bool get existingAccount => _existingAccount;
  bool get busy => !_disposed && _busy;
  String? get error => _error;
  bool get creatingAccount => _entry != SignInEntry.signIn && !_existingAccount;
  void clearError() {
    _error = null;
  }

  void _select(SignInEntry entry) {
    _entry = entry;
    _existingAccount = false;
    _error = null;
  }

  void selectEntry(SignInEntry entry) {
    if (!_disposed && !_busy) _select(entry);
  }

  void toggleExisting() {
    if (_disposed || _busy || _entry != SignInEntry.join) return;
    _existingAccount = !_existingAccount;
    _error = null;
  }

  static String? requiredValue(String? value, String label) =>
      (value ?? '').trim().isEmpty
      ? 'Enter your ${label.toLowerCase()}.'
      : null;
  String? validateUsername(String? value) => _entry == SignInEntry.signIn
      ? requiredValue(value, 'username')
      : isEmailAddress(value ?? '')
      ? null
      : 'Enter a valid email address.';
  String? validatePassword(String? value) => (value ?? '').isEmpty
      ? 'Enter your password.'
      : creatingAccount && value!.length < 10
      ? 'Use at least 10 characters.'
      : null;
  String? _validate(SignInValues values) =>
      validateUsername(values.username) ??
      validatePassword(values.password) ??
      (creatingAccount ? requiredValue(values.fullName, 'full name') : null) ??
      (_entry == SignInEntry.owner
          ? requiredValue(values.company, 'company name')
          : null) ??
      (_entry == SignInEntry.join
          ? requiredValue(values.invitation, 'invitation code')
          : null);
  bool _active(int at) => !_disposed && at == _generation;
  Future<SignInResult> submit(SignInValues values) async {
    if (_disposed || _busy) return SignInResult.ignored;
    final invalid = _validate(values);
    if (invalid != null) {
      _error = invalid;
      return SignInResult.failed;
    }
    final at = ++_generation, entry = _entry, existing = _existingAccount;
    _busy = true;
    _error = null;
    String? completed;
    try {
      switch (entry) {
        case SignInEntry.owner:
          await _repository.registerOwner(values, industry: industry);
          completed = 'Your company was created.';
        case SignInEntry.join:
          if (existing) {
            await _repository.joinExisting(values);
          } else {
            await _repository.joinNew(values);
          }
          completed = 'You joined the company.';
        case SignInEntry.signIn:
          break;
      }
      if (!_active(at)) return SignInResult.ignored;
      await _signIn(values.username.trim(), values.password);
      return _active(at) ? SignInResult.signedIn : SignInResult.ignored;
    } catch (error) {
      if (!_active(at)) return SignInResult.ignored;
      if (completed != null) _select(SignInEntry.signIn);
      _error = completed == null
          ? error.toString()
          : '$completed Sign in to continue. $error';
      return completed == null
          ? SignInResult.failed
          : SignInResult.signInRequired;
    } finally {
      if (_active(at)) _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _error = null;
  }
}
