import 'package:flutter/material.dart';

import '../../core/models/erp_exception.dart';
import '../../erp_api.dart' show ErpApi;
import '../../features/authentication/data/erp_onboarding_repository.dart';
import '../../features/authentication/presentation/sign_in_view.dart';
import '../../features/authentication/presentation/sign_in_view_model.dart';
import 'session_recovery.dart';

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
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  Object _lifetime = Object();
  late SignInViewModel _model = _createModel();
  SignInViewModel _createModel([SignInViewModel? previous]) {
    final lifetime = _lifetime;
    final repository = ErpOnboardingRepository(
      connect: widget.connect,
      authenticate: (api, username, password) async {
        if (!mounted || !identical(_lifetime, lifetime)) {
          throw const ErpException('Sign-in was cancelled.');
        }
        await signInWithVerification(context, api, username, password);
        if (!mounted || !identical(_lifetime, lifetime)) {
          throw const ErpException('Sign-in was cancelled.');
        }
      },
    );
    return previous == null
        ? SignInViewModel(repository, signIn: widget.onSignIn)
        : SignInViewModel(
            repository,
            signIn: widget.onSignIn,
            entry: previous.entry,
            industry: previous.industry,
            existingAccount: previous.existingAccount,
          );
  }

  @override
  void didUpdateWidget(covariant SignInScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connect != widget.connect ||
        oldWidget.onSignIn != widget.onSignIn) {
      final previous = _model;
      previous.dispose();
      _lifetime = Object();
      _model = _createModel(previous);
    }
  }

  @override
  void dispose() {
    _lifetime = Object();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SignInView(model: _model, onLicenses: widget.onLicenses);
}
