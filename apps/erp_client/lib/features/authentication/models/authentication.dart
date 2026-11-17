enum SignInEntry { signIn, owner, join }

enum SignInResult { signedIn, signInRequired, failed, ignored }

enum LoginResult { signedIn, verificationRequired, failed, ignored }

/// A single command input. Credentials are not retained in presentation state.
class SignInValues {
  const SignInValues({
    required this.username,
    required this.password,
    this.fullName = '',
    this.company = '',
    this.invitation = '',
  });
  final String username, password, fullName, company, invitation;
}
