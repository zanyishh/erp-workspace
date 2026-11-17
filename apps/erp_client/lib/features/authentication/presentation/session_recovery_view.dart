import 'package:flutter/material.dart';

import '../models/authentication.dart';
import 'session_login_view_model.dart';

class SessionRecoveryView extends StatefulWidget {
  const SessionRecoveryView({
    super.key,
    required this.model,
    required this.account,
    required this.verify,
  });
  final SessionLoginViewModel model;
  final String account;
  final Future<bool> Function(VerificationViewModel) verify;
  @override
  State<SessionRecoveryView> createState() => _SessionRecoveryViewState();
}

class _SessionRecoveryViewState extends State<SessionRecoveryView> {
  final _password = TextEditingController();
  bool get _busy => widget.model.busy;
  String? get _error => widget.model.error;
  @override
  void didUpdateWidget(covariant SessionRecoveryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) _password.clear();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final model = widget.model;
    final next = model.signIn(widget.account, _password.text);
    setState(() {});
    final result = await next;
    if (!mounted || !identical(model, widget.model)) return;
    var signedIn = result == LoginResult.signedIn;
    if (result == LoginResult.verificationRequired) {
      signedIn = await widget.verify(model.verification);
      if (!mounted || !identical(model, widget.model)) return;
      if (!signedIn) model.cancelVerification();
    }
    if (signedIn) {
      Navigator.pop(context, true);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Sign in again'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.account),
            const SizedBox(height: 16),
            const Text(
              'Your edits are still here. Sign in, then retry your last action. Signing out discards unsaved edits.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _signIn(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_error!)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Sign out'),
        ),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
      ],
    ),
  );
}
