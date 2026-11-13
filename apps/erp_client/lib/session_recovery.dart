import 'package:flutter/material.dart';
import 'erp_api.dart';

Future<void> signInWithVerification(
  BuildContext context,
  ErpApi api,
  String username,
  String password,
) async {
  try {
    await api.login(username, password);
  } on LoginVerification catch (challenge) {
    if (!context.mounted) throw const ErpException('Sign-in was cancelled.');
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerificationDialog(
        prompt: challenge.prompt,
        verify: (code) => api.verifyLogin(username, challenge, code),
      ),
    );
    if (verified != true) {
      throw const ErpException(
        'Sign in again to request a new verification code.',
      );
    }
  }
}

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({required this.prompt, required this.verify});
  final String prompt;
  final Future<void> Function(String) verify;
  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your verification code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.verify(code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Verify your sign-in'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.prompt),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              autofillHints: const [AutofillHints.oneTimeCode],
              keyboardType: TextInputType.number,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_busy,
              onSubmitted: (_) => _verify(),
              decoration: const InputDecoration(labelText: 'Verification code'),
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
          child: const Text('Back to sign-in'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? 'Verifying…' : 'Verify'),
        ),
      ],
    ),
  );
}

class SessionRecoveryDialog extends StatefulWidget {
  const SessionRecoveryDialog({super.key, required this.api});
  final ErpApi api;
  @override
  State<SessionRecoveryDialog> createState() => _SessionRecoveryDialogState();
}

class _SessionRecoveryDialogState extends State<SessionRecoveryDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signInWithVerification(
        context,
        widget.api,
        widget.api.account,
        _password.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
            Text(widget.api.account),
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
