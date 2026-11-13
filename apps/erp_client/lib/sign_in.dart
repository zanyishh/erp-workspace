import 'ui/workspace_art.dart';
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
    text:
        const String.fromEnvironment('ERP_SERVER', defaultValue: '').isNotEmpty
        ? const String.fromEnvironment('ERP_SERVER')
        : Platform.isAndroid
        ? 'http://10.0.2.2:8081'
        : 'http://localhost:8081',
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
    body: WorkspaceBackdrop(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final wide = viewport.maxWidth >= 900;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                wide ? 40 : 18,
                20,
                wide ? 40 : 18,
                24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (viewport.maxHeight - 44)
                      .clamp(0, double.infinity)
                      .toDouble(),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.dashboard_customize_rounded,
                                size: 24,
                              ),
                              const SizedBox(width: 9),
                              const Expanded(
                                child: Display('ERP Workspace', size: 27),
                              ),
                              TextButton(
                                onPressed: widget.onLicenses,
                                child: const Text('Licenses'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (wide)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: Stack(
                                alignment: Alignment.centerRight,
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFFD9DAD7),
                                            Color(0xFFF4F4F2),
                                            Color(0xFFDFDFDD),
                                          ],
                                        ),
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: .68,
                                          child: const WorkspaceArt(
                                            ArtObject.warehouse,
                                            width: double.infinity,
                                            height: 400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: SizedBox(width: 370, child: _form()),
                                  ),
                                ],
                              ),
                            )
                          else
                            _form(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  Widget _form() => Panel(
    dark: true,
    frosted: true,
    padding: const EdgeInsets.all(25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Display('Sign in', size: 40, light: true),
        const SizedBox(height: 8),
        const Text(
          'Use your company’s ERPNext account.',
          style: TextStyle(color: Color(0xFFD7DFD7)),
        ),
        const SizedBox(height: 22),
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
