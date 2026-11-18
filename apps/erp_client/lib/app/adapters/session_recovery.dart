import 'package:flutter/material.dart';

import '../../core/models/erp_exception.dart';
import '../../erp_api.dart' show ErpApi;
import '../../features/authentication/data/erp_session_repository.dart';
import '../../features/authentication/models/authentication.dart';
import '../../features/authentication/presentation/session_login_view_model.dart';
import '../../features/authentication/presentation/session_recovery_view.dart';
import '../../features/authentication/presentation/verification_dialog.dart';

Future<bool> _verify(BuildContext context, VerificationViewModel model) async {
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VerificationDialogView(model: model),
      ) ==
      true;
}

Future<void> signInWithVerification(
  BuildContext context,
  ErpApi api,
  String username,
  String password,
) async {
  final model = SessionLoginViewModel(ErpSessionRepository(api));
  try {
    final result = await model.signIn(username, password);
    if (result == LoginResult.signedIn) return;
    if (result == LoginResult.verificationRequired) {
      if (!context.mounted) throw const ErpException('Sign-in was cancelled.');
      if (await _verify(context, model.verification)) return;
      model.cancelVerification();
    }
    throw model.failure ?? const ErpException('Sign-in was cancelled.');
  } finally {
    model.dispose();
  }
}

class SessionRecoveryDialog extends StatefulWidget {
  const SessionRecoveryDialog({super.key, required this.api});
  final ErpApi api;
  @override
  State<SessionRecoveryDialog> createState() => _SessionRecoveryState();
}

class _SessionRecoveryState extends State<SessionRecoveryDialog> {
  late SessionLoginViewModel _model = _createModel();
  SessionLoginViewModel _createModel() => SessionLoginViewModel(
    ErpSessionRepository(widget.api),
    recoveryAccount: widget.api.account,
  );
  @override
  void didUpdateWidget(covariant SessionRecoveryDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        _model.recoveryAccount != widget.api.account) {
      _model.dispose();
      _model = _createModel();
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SessionRecoveryView(
    model: _model,
    account: _model.recoveryAccount!,
    verify: (model) => _verify(context, model),
  );
}
