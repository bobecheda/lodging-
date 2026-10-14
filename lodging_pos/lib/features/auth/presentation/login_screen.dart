import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gate_card.dart';
import '../../../core/auth/session.dart';
import '../domain/login.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(loginServiceProvider)
          .login(_username.text, _password.text);
      if (result.outcome.signsIn) {
        // The router takes it from here.
        ref.read(sessionProvider.notifier).signIn(result.user!);
        return;
      }
      _password.clear();
      setState(() {
        _error = switch (result.outcome) {
          LoginOutcome.disabled =>
            'This account is disabled. Ask the admin to enable it.',
          _ => 'Wrong username or password.',
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GateCard(
    title: 'Sign in',
    children: [
      TextField(
        key: const ValueKey('login.username'),
        controller: _username,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Username'),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('login.password'),
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      FormError(_error),
      BusyButton(
        key: const ValueKey('login.submit'),
        label: 'Sign in',
        busy: _busy,
        onPressed: _submit,
      ),
    ],
  );
}
