import 'package:flutter/material.dart';
import 'erp_api.dart';

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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(widget.api.account, _password.text);
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
      title: const Text('Sign in again'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.api.account}\n${widget.api.baseUri}'),
            const SizedBox(height: 16),
            const Text(
              'Your edits are still here. Sign in, then retry your last action. Signing out discards unsaved edits.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _signIn(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
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
