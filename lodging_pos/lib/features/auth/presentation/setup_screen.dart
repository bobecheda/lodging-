import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gate_card.dart';
import '../data/user_repository.dart';
import '../domain/setup.dart';
import 'auth_providers.dart';

/// First run only: creates the admin and names the lodging. Unreachable
/// once any user exists (see the router).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _fields = {
    for (final f in SetupField.values) f: TextEditingController(),
  };
  var _errors = <SetupField, String>{};
  String? _formError;
  var _busy = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  SetupInput get _input => SetupInput(
    fullName: _fields[SetupField.fullName]!.text,
    username: _fields[SetupField.username]!.text,
    password: _fields[SetupField.password]!.text,
    confirmPassword: _fields[SetupField.confirmPassword]!.text,
    lodgingName: _fields[SetupField.lodgingName]!.text,
  );

  Future<void> _submit() async {
    final errors = validateSetup(_input);
    setState(() {
      _errors = errors;
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(userRepositoryProvider).createFirstAdmin(_input);
      // The router moves on to the login screen.
      ref.read(setupStatusProvider.notifier).markDone();
    } on SetupAlreadyDone {
      ref.read(setupStatusProvider.notifier).markDone();
    } catch (e) {
      if (mounted) setState(() => _formError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    SetupField field,
    String label, {
    bool obscure = false,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey('setup.${field.name}'),
      controller: _fields[field],
      obscureText: obscure,
      decoration: InputDecoration(labelText: label, errorText: _errors[field]),
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _submit() : null,
    ),
  );

  @override
  Widget build(BuildContext context) => GateCard(
    title: 'Set up this lodging',
    subtitle: 'Create the admin account. You can add receptionists later.',
    children: [
      _field(SetupField.lodgingName, 'Lodging name (printed on receipts)'),
      _field(SetupField.fullName, 'Your full name'),
      _field(SetupField.username, 'Username'),
      _field(SetupField.password, 'Password', obscure: true),
      _field(
        SetupField.confirmPassword,
        'Confirm password',
        obscure: true,
        last: true,
      ),
      FormError(_formError),
      BusyButton(
        key: const ValueKey('setup.submit'),
        label: 'Create admin account',
        busy: _busy,
        onPressed: _submit,
      ),
    ],
  );
}
