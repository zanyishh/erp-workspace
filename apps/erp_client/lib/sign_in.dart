import 'dart:io';
import 'package:flutter/material.dart';
import 'design.dart';
import 'widgets.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.onSignIn,
    required this.onLicenses,
  });
  final Future<void> Function(String server, String username, String password)
  onSignIn;
  final VoidCallback onLicenses;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _server = TextEditingController(
    text: Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080',
  );
  final _username = TextEditingController(text: 'Administrator');
  final _password = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignIn(
        _server.text.trim(),
        _username.text.trim(),
        _password.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, b) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: b.maxHeight),
            child: Padding(
              padding: EdgeInsets.all(b.maxWidth > 780 ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      const Display('WORKSPACE.', size: 30),
                      TextButton(
                        onPressed: widget.onLicenses,
                        child: const Text(
                          'Open source · Licenses',
                          style: TextStyle(
                            fontSize: 11,
                            color: WorkspaceTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: b.maxWidth > 900 ? 66 : 24),
                  if (b.maxWidth >= 900)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const StatusChip('Powered by ERPNext'),
                              const SizedBox(height: 28),
                              const Display(
                                'YOUR BUSINESS.\nONE CLEAR VIEW.',
                                size: 70,
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Everything you run, brought together.\nA quieter place to make things happen.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.8,
                                  color: WorkspaceTheme.muted,
                                ),
                              ),
                              const SizedBox(height: 15),
                              Image.asset(
                                'assets/images/warehouse.png',
                                height: 295,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 65),
                        Expanded(flex: 4, child: _form()),
                      ],
                    )
                  else ...[
                    const Display('YOUR BUSINESS.\nONE CLEAR VIEW.', size: 43),
                    const SizedBox(height: 12),
                    Image.asset(
                      'assets/images/warehouse.png',
                      height: 165,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    _form(),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'An independent open source workspace, connected to ERPNext.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: WorkspaceTheme.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _form() => Panel(
    dark: true,
    padding: const EdgeInsets.all(25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusChip('Welcome back', dark: true),
        const SizedBox(height: 25),
        const Display('MAKE YOURSELF\nAT WORK.', size: 42, light: true),
        const SizedBox(height: 13),
        const Text(
          'Sign in with your ERPNext account.',
          style: TextStyle(fontSize: 12, color: Color(0xFFBCC3B6)),
        ),
        const SizedBox(height: 28),
        _label('ERPNext address'),
        TextField(
          controller: _server,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(fontSize: 12, color: WorkspaceTheme.ink),
          decoration: const InputDecoration(
            hintText: 'https://your-company.example',
          ),
        ),
        const SizedBox(height: 17),
        _label('Username'),
        TextField(
          controller: _username,
          enabled: !_busy,
          autocorrect: false,
          style: const TextStyle(fontSize: 13, color: WorkspaceTheme.ink),
          decoration: const InputDecoration(hintText: 'Your username'),
        ),
        const SizedBox(height: 17),
        _label('Password'),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 13, color: WorkspaceTheme.ink),
          decoration: InputDecoration(
            hintText: 'Your password',
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Text(
              _error!,
              style: const TextStyle(
                color: WorkspaceTheme.palePeach,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: WorkspaceTheme.palePeach,
              foregroundColor: WorkspaceTheme.ink,
              minimumSize: const Size(44, 52),
              shape: const StadiumBorder(),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WorkspaceTheme.ink,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'Enter workspace',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(width: 9),
                      Icon(Icons.arrow_forward, size: 17),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'Your password stays in memory for this session.',
          style: TextStyle(fontSize: 10, color: Color(0xFFBCC3B6)),
        ),
      ],
    ),
  );
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: Color(0xFFD6DBD0)),
    ),
  );
}
