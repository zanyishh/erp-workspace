class ErpException implements Exception {
  const ErpException(
    this.message, {
    this.sessionExpired = false,
    this.permissionDenied = false,
    this.staleDocument = false,
    this.validationRejected = false,
  });
  final String message;
  final bool sessionExpired;
  final bool permissionDenied;
  final bool staleDocument;
  final bool validationRejected;
  @override
  String toString() => message;
}

class LoginVerification implements Exception {
  const LoginVerification(this.temporaryId, this.prompt);
  final String temporaryId, prompt;
  @override
  String toString() => prompt;
}
