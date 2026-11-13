import 'package:flutter/material.dart';
import 'design.dart';
import 'erp_api.dart';
import 'session_recovery.dart';
import 'ui/workspace_art.dart';
import 'ui/workspace_ui.dart';
import 'widgets.dart';

enum _Entry { signIn, owner, join }

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.connect,
    required this.onSignIn,
    required this.onLicenses,
  });
  final ErpApi Function() connect;
  final Future<void> Function(String username, String password) onSignIn;
  final VoidCallback onLicenses;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _code = TextEditingController();
  var _formKey = GlobalKey<FormState>();
  var _entry = _Entry.signIn;
  String _industry = 'general';
  bool _busy = false, _obscure = true, _existing = false, _submitted = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [_username, _password, _name, _company, _code]) {
      field.dispose();
    }
    super.dispose();
  }

  void _switch(_Entry entry) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _entry = entry;
      _formKey = GlobalKey<FormState>();
      _error = null;
      _existing = false;
      _obscure = true;
      _submitted = false;
      _password.clear();
      _code.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _submitted = true;
        _error = null;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _username.text.trim();
    final password = _password.text;
    final joiningExisting = _entry == _Entry.join && _existing;
    String? completed;
    try {
      if (_entry != _Entry.signIn) {
        final api = widget.connect();
        try {
          if (_entry == _Entry.owner) {
            await api.registerOwner(
              fullName: _name.text.trim(),
              email: email,
              password: password,
              company: _company.text.trim(),
              industry: _industry,
            );
            completed = 'Your company was created.';
          } else if (joiningExisting) {
            await api.redeemExistingInvitation(
              _code.text.trim(),
              () => signInWithVerification(context, api, email, password),
            );
            completed = 'You joined the company.';
          } else {
            await api.acceptInvitation(
              _code.text.trim(),
              fullName: _name.text.trim(),
              email: email,
              password: password,
            );
            completed = 'You joined the company.';
          }
        } finally {
          api.close();
        }
      }
      if (!mounted) return;
      await widget.onSignIn(email, password);
    } catch (e) {
      if (mounted) {
        if (completed != null) _switch(_Entry.signIn);
        setState(
          () => _error = completed == null
              ? e.toString()
              : '$completed Sign in to continue. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _workspacePreview(BuildContext context, {required bool wide}) {
    final object = _entry == _Entry.owner && _industry == 'knitting'
        ? ArtObject.machine
        : ArtObject.warehouse;
    return AnimatedSwitcher(
      duration: workspaceMotion(context),
      child: WorkspaceArt(
        object,
        key: ValueKey(object),
        width: wide ? double.infinity : 60,
        height: wide ? 360 : 44,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _entry == _Entry.signIn && !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy && _entry != _Entry.signIn) _switch(_Entry.signIn);
    },
    child: Scaffold(
      body: WorkspaceBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final wide = viewport.maxWidth >= 900;
              final inset = wide ? 40.0 : 18.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(inset, 20, inset, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (viewport.maxHeight - 44).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 1080 : 470),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (wide)
                                const Icon(
                                  Icons.dashboard_customize_rounded,
                                  size: 24,
                                )
                              else
                                _workspacePreview(context, wide: false),
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
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFDFE0DC),
                                      Color(0xFFF2F2EE),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _workspacePreview(
                                        context,
                                        wide: true,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: SizedBox(
                                        width: 410,
                                        child: _form(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            _form(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _form() {
    final signIn = _entry == _Entry.signIn;
    final owner = _entry == _Entry.owner;
    final creatingAccount = !signIn && !_existing;
    final heading = signIn
        ? 'Sign in'
        : owner
        ? 'Create a company'
        : 'Join your team';
    return Panel(
      dark: true,
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Display(heading, size: 40, light: true),
              const SizedBox(height: 8),
              Text(
                signIn
                    ? 'Sign in to your company workspace.'
                    : owner
                    ? 'Set up your workspace and invite your staff.'
                    : 'Enter the code your workspace manager shared with you.',
                style: const TextStyle(color: WorkspaceTheme.light),
              ),
              const SizedBox(height: 20),
              if (_entry == _Entry.join) ...[
                _input(
                  _code,
                  'Invitation code',
                  Icons.key_outlined,
                  autocorrect: false,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: _lightLink,
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _existing = !_existing;
                            _formKey = GlobalKey<FormState>();
                            _submitted = false;
                            _error = null;
                            _password.clear();
                          }),
                    child: Text(
                      _existing
                          ? 'Create a new account'
                          : 'Use an existing account',
                    ),
                  ),
                ),
              ],
              if (creatingAccount) ...[
                _input(
                  _name,
                  'Full name',
                  Icons.person_outline,
                  hints: const [AutofillHints.name],
                ),
                const SizedBox(height: 12),
              ],
              _input(
                _username,
                signIn ? 'Username' : 'Email',
                signIn ? Icons.person_outline : Icons.alternate_email,
                type: TextInputType.emailAddress,
                autocorrect: false,
                hints: [signIn ? AutofillHints.username : AutofillHints.email],
                validate: signIn
                    ? (v) => (v ?? '').trim().isEmpty
                          ? 'Enter your username.'
                          : null
                    : _emailError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [
                  creatingAccount
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                textInputAction: owner
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: owner ? null : (_) => _submit(),
                validator: (v) => (v ?? '').isEmpty
                    ? 'Enter your password.'
                    : creatingAccount && v!.length < 10
                    ? 'Use at least 10 characters.'
                    : null,
                decoration: _field('Password', Icons.lock_outline).copyWith(
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
              if (owner) ...[
                const SizedBox(height: 12),
                _input(
                  _company,
                  'Company name',
                  Icons.business_outlined,
                  hints: const [AutofillHints.organizationName],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _industry,
                  isExpanded: true,
                  decoration: _field('Workspace', Icons.workspaces_outline),
                  items: const [
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('General ERP'),
                    ),
                    DropdownMenuItem(
                      value: 'knitting',
                      child: Text('Knitting'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _industry = v!),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: WorkspaceTheme.palePeach),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: WorkspaceTheme.palePeach,
                  foregroundColor: WorkspaceTheme.ink,
                  minimumSize: const Size(44, 50),
                ),
                child: Text(
                  _busy
                      ? owner
                            ? 'Creating company…'
                            : 'Connecting…'
                      : signIn
                      ? 'Enter workspace'
                      : owner
                      ? 'Create workspace'
                      : 'Join workspace',
                ),
              ),
              const SizedBox(height: 6),
              if (signIn)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      style: _lightLink,
                      onPressed: _busy ? null : () => _switch(_Entry.owner),
                      child: const Text('Create a company'),
                    ),
                    TextButton(
                      style: _lightLink,
                      onPressed: _busy ? null : () => _switch(_Entry.join),
                      child: const Text('Join with invitation'),
                    ),
                  ],
                )
              else
                TextButton(
                  style: _lightLink,
                  onPressed: _busy ? null : () => _switch(_Entry.signIn),
                  child: const Text('Back to sign-in'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static final _lightLink = TextButton.styleFrom(
    foregroundColor: WorkspaceTheme.light,
  );
  static String? _emailError(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Enter a valid email address.';

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    Iterable<String>? hints,
    TextInputType? type,
    bool autocorrect = true,
    FormFieldValidator<String>? validate,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    autofillHints: hints,
    keyboardType: type,
    autocorrect: autocorrect,
    textInputAction: TextInputAction.next,
    validator:
        validate ??
        (v) => (v ?? '').trim().isEmpty
            ? 'Enter your ${label.toLowerCase()}.'
            : null,
    decoration: _field(label, icon),
  );

  static final _filledBorder = UnderlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  );
  InputDecoration _field(String label, IconData icon) => InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    floatingLabelStyle: const TextStyle(color: WorkspaceTheme.muted),
    enabledBorder: _filledBorder,
    border: _filledBorder,
    focusedBorder: _filledBorder.copyWith(
      borderSide: const BorderSide(color: WorkspaceTheme.peach, width: 2),
    ),
    errorBorder: _filledBorder.copyWith(
      borderSide: const BorderSide(color: WorkspaceTheme.peach),
    ),
    focusedErrorBorder: _filledBorder.copyWith(
      borderSide: const BorderSide(color: WorkspaceTheme.peach, width: 2),
    ),
    prefixIcon: Icon(icon, size: 19),
    errorMaxLines: 3,
    errorStyle: const TextStyle(color: WorkspaceTheme.palePeach),
  );
}
