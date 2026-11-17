import 'package:flutter/material.dart';

import 'session_login_view_model.dart';

class VerificationDialogView extends StatefulWidget {
  const VerificationDialogView({super.key, required this.model});
  final VerificationViewModel model;
  @override
  State<VerificationDialogView> createState() => _VerificationDialogViewState();
}

class _VerificationDialogViewState extends State<VerificationDialogView> {
  final _code = TextEditingController();
  bool get _busy => widget.model.busy;
  String? get _error => widget.model.error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final model = widget.model;
    final next = model.verify(_code.text);
    setState(() {});
    final success = await next;
    if (!mounted || !identical(model, widget.model)) return;
    if (model.disposed) {
      Navigator.pop(context, false);
    } else if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {});
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
            Text(widget.model.prompt),
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
