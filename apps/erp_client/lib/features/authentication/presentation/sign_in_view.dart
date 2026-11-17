import 'package:flutter/material.dart';

import '../../../core/ui/design.dart';
import '../../../core/ui/workspace_art.dart';
import '../../../core/ui/workspace_ui.dart';
import '../../../core/ui/widgets.dart';
import '../models/authentication.dart';
import 'sign_in_view_model.dart';

class SignInView extends StatefulWidget {
  const SignInView({super.key, required this.model, required this.onLicenses});
  final SignInViewModel model;
  final VoidCallback onLicenses;
  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _company = TextEditingController(),
      _code = TextEditingController();
  var _formKey = GlobalKey<FormState>();
  bool _obscure = true, _submitted = false;
  SignInEntry get _entry => widget.model.entry;
  bool get _existing => widget.model.existingAccount;
  bool get _busy => widget.model.busy;
  String? get _error => widget.model.error;
  String get _industry => widget.model.industry;
  set _industry(String value) => widget.model.industry = value;
  void _resetForm() {
    _formKey = GlobalKey<FormState>();
    _obscure = true;
    _submitted = false;
    _password.clear();
    _code.clear();
  }

  @override
  void didUpdateWidget(covariant SignInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) _resetForm();
  }

  @override
  void dispose() {
    for (final field in [_username, _password, _name, _company, _code]) {
      field.dispose();
    }
    super.dispose();
  }

  void _switch(SignInEntry entry) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      widget.model.selectEntry(entry);
      _resetForm();
    });
  }

  Future<void> _submit() async {
    final model = widget.model;
    if (model.busy) return;
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _submitted = true;
        model.clearError();
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final next = model.submit(
      SignInValues(
        username: _username.text,
        password: _password.text,
        fullName: _name.text,
        company: _company.text,
        invitation: _code.text,
      ),
    );
    setState(() {});
    final result = await next;
    if (!mounted || !identical(model, widget.model)) return;
    setState(() {
      if (result == SignInResult.signInRequired) {
        FocusManager.instance.primaryFocus?.unfocus();
        _resetForm();
      }
    });
  }

  Widget _workspacePreview(BuildContext context, {required bool wide}) {
    final object = _entry == SignInEntry.owner && _industry == 'knitting'
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
    canPop: _entry == SignInEntry.signIn && !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy && _entry != SignInEntry.signIn) {
        _switch(SignInEntry.signIn);
      }
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
    final signIn = _entry == SignInEntry.signIn;
    final owner = _entry == SignInEntry.owner;
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
              if (_entry == SignInEntry.join) ..._invitationFields(),
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
                validate: widget.model.validateUsername,
              ),
              const SizedBox(height: 12),
              _passwordField(owner: owner, creatingAccount: creatingAccount),
              if (owner) ..._companyFields(),
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
                      onPressed: _busy
                          ? null
                          : () => _switch(SignInEntry.owner),
                      child: const Text('Create a company'),
                    ),
                    TextButton(
                      style: _lightLink,
                      onPressed: _busy ? null : () => _switch(SignInEntry.join),
                      child: const Text('Join with invitation'),
                    ),
                  ],
                )
              else
                TextButton(
                  style: _lightLink,
                  onPressed: _busy ? null : () => _switch(SignInEntry.signIn),
                  child: const Text('Back to sign-in'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _invitationFields() => [
    _input(_code, 'Invitation code', Icons.key_outlined, autocorrect: false),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: _lightLink,
        onPressed: _busy
            ? null
            : () => setState(() {
                widget.model.toggleExisting();
                _formKey = GlobalKey<FormState>();
                _submitted = false;
                _password.clear();
              }),
        child: Text(
          _existing ? 'Create a new account' : 'Use an existing account',
        ),
      ),
    ),
  ];

  List<Widget> _companyFields() => [
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
      decoration: _field('Industry', Icons.workspaces_outline),
      items: const [
        DropdownMenuItem(value: 'general', child: Text('General ERP')),
        DropdownMenuItem(value: 'knitting', child: Text('Knitting')),
      ],
      onChanged: _busy ? null : (v) => setState(() => _industry = v!),
    ),
  ];

  Widget _passwordField({required bool owner, required bool creatingAccount}) =>
      TextFormField(
        controller: _password,
        enabled: !_busy,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [
          creatingAccount ? AutofillHints.newPassword : AutofillHints.password,
        ],
        textInputAction: owner ? TextInputAction.next : TextInputAction.done,
        onFieldSubmitted: owner ? null : (_) => _submit(),
        validator: widget.model.validatePassword,
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
      );

  static final _lightLink = TextButton.styleFrom(
    foregroundColor: WorkspaceTheme.light,
  );
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
        validate ?? (value) => SignInViewModel.requiredValue(value, label),
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
