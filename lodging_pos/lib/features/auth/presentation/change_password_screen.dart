import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/split_gate_layout.dart';
import '../../../core/auth/session.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';

/// Shown right after sign-in when `must_change_password` is set; the router
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
  Widget build(BuildContext context) => SplitGateLayout(
    title: 'Choose a new password',
    subtitle:
        'The owner gave you a temporary password. Choose your own to carry on.',
    children: [
      LabeledField(
        label: 'New password',
        controller: _password,
        fieldKey: const ValueKey('password.new'),
        obscureText: true,
        autofocus: true,
        helperText: 'At least $minPasswordLength characters',
        errorText: _errors[PasswordField.password],
        textInputAction: TextInputAction.next,
      ),
      formGap,
      LabeledField(
        label: 'Confirm new password',
        controller: _confirm,
        fieldKey: const ValueKey('password.confirm'),
        obscureText: true,
        errorText: _errors[PasswordField.confirm],
        onSubmitted: (_) => _submit(),
      ),
      formGap,
      if (_formError != null) ...[Note.error(_formError!), formGap],
      AppButton.primary(
        key: const ValueKey('password.submit'),
        label: 'Save password',
        large: true,
        busy: _busy,
        onPressed: _submit,
      ),
      const SizedBox(height: 8),
      AppButton.secondary(
        key: const ValueKey('password.signOut'),
        label: 'Sign out',
        onPressed: () => ref.read(sessionProvider.notifier).signOut(),
      ),
    ],
  );
}
