import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gate_card.dart';
import '../../../core/auth/session.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';

/// Shown right after login when `must_change_password` is set; the router
/// keeps every other screen out of reach until it is done.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _errors = <PasswordField, String>{};
  String? _formError;
  var _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final errors = newPasswordErrors(_password.text, _confirm.text);
    setState(() {
      _errors = errors;
      _formError = null;
    });
    final user = ref.read(sessionProvider);
    if (errors.isNotEmpty || user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .changePassword(user.id, _password.text);
      ref.read(sessionProvider.notifier).passwordChanged();
    } catch (e) {
      if (mounted) setState(() => _formError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GateCard(
    title: 'Choose a new password',
    subtitle:
        'Your password was set by the admin. Choose your own to continue.',
    children: [
      TextField(
        key: const ValueKey('password.new'),
        controller: _password,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'New password',
          helperText: 'At least $minPasswordLength characters',
          errorText: _errors[PasswordField.password],
        ),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('password.confirm'),
        controller: _confirm,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Confirm new password',
          errorText: _errors[PasswordField.confirm],
        ),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      FormError(_formError),
      BusyButton(
        key: const ValueKey('password.submit'),
        label: 'Save password',
        busy: _busy,
        onPressed: _submit,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => ref.read(sessionProvider.notifier).signOut(),
        child: const Text('Sign out'),
      ),
    ],
  );
}
