import '../../../core/models/erp_exception.dart';
import '../data/session_repository.dart';
import '../models/authentication.dart';

const _cancelled = ErpException('Sign-in was cancelled.');
const _newCode = ErpException(
  'Sign in again to request a new verification code.',
);

class SessionLoginViewModel {
  SessionLoginViewModel(this._repository, {this.recoveryAccount})
    : _identity = _repository.identity;
  final SessionRepository _repository;
  final Object _identity;
  final String? recoveryAccount;
  bool _busy = false, _disposed = false;
  Object? _failure;
  LoginVerification? _challenge;
  String? _username;
  VerificationViewModel? _verification;
  bool get disposed => _disposed;
  bool get busy => !_disposed && _busy;
  Object? get failure => _failure;
  String? get error => _failure?.toString();
  bool get _current =>
      !_disposed &&
      _identity == _repository.identity &&
      (recoveryAccount == null || recoveryAccount == _repository.account);
  Future<LoginResult> signIn(String username, String password) async {
    if (_disposed || _busy) return LoginResult.ignored;
    if (!_current || recoveryAccount != null && username != recoveryAccount) {
      _failure = _cancelled;
      return LoginResult.failed;
    }
    if (password.isEmpty) {
      _failure = const ErpException('Enter your password.');
      return LoginResult.failed;
    }
    _busy = true;
    _failure = null;
    _verification?.dispose();
    _verification = null;
    _challenge = null;
    _username = username;
    try {
      final challenge = await _repository.signIn(username, password);
      if (!_current) return LoginResult.ignored;
      _challenge = challenge;
      return challenge == null
          ? LoginResult.signedIn
          : LoginResult.verificationRequired;
    } catch (error) {
      if (!_current) return LoginResult.ignored;
      _failure = error;
      return LoginResult.failed;
    } finally {
      _busy = _current && _challenge != null;
    }
  }

  VerificationViewModel get verification {
    if (!_current || _challenge == null) {
      throw StateError('No current sign-in challenge.');
    }
    return _verification ??= VerificationViewModel(
      _repository,
      _username!,
      _challenge!,
      recoveryAccount: recoveryAccount,
      onVerified: () {
        if (_current) {
          _busy = false;
          _challenge = null;
        }
      },
    );
  }

  void cancelVerification() {
    if (_disposed) return;
    _failure = _current ? _newCode : _cancelled;
    _busy = false;
    _challenge = null;
    _verification?.dispose();
    _verification = null;
  }

  void dispose() {
    _disposed = true;
    _verification?.dispose();
    _failure = null;
    _challenge = null;
  }
}

class VerificationViewModel {
  VerificationViewModel(
    this._repository,
    this._username,
    this._challenge, {
    this.recoveryAccount,
    this._onVerified,
  }) : _identity = _repository.identity;
  final SessionRepository _repository;
  final String _username;
  final LoginVerification _challenge;
  final Object _identity;
  final String? recoveryAccount;
  final void Function()? _onVerified;
  bool _disposed = false, _busy = false;
  String? _error;
  String get prompt => _challenge.prompt;
  String? get error => _error;
  bool get busy => !_disposed && _busy;
  bool get disposed => _disposed;
  bool get _current =>
      !_disposed &&
      _identity == _repository.identity &&
      (recoveryAccount == null || recoveryAccount == _repository.account);
  Future<bool> verify(String input) async {
    if (!_current || _busy) return false;
    final code = input.trim();
    if (code.isEmpty) {
      _error = 'Enter your verification code.';
      return false;
    }
    _busy = true;
    _error = null;
    try {
      await _repository.verify(_username, _challenge, code);
      if (!_current) return false;
      _onVerified?.call();
      return true;
    } catch (error) {
      if (_current) _error = error.toString();
      return false;
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _error = null;
  }
}
