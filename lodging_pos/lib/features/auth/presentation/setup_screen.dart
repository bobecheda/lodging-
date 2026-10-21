import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/split_gate_layout.dart';
import '../../../core/settings/settings_repository.dart';
import '../data/user_repository.dart';
import '../domain/setup.dart';
import 'auth_providers.dart';

/// First run only: creates the supervisor's account and names the
/// lodging. (Sprint 2: first run creates the owner, who then creates the
/// supervisor; prd.md, open items.)
/// Unreachable once any user exists (see the router).
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
      await ref.read(userRepositoryProvider).createFirstSupervisor(_input);
      _done();
    } on SetupAlreadyDone {
      _done();
    } catch (e) {
      if (mounted) setState(() => _formError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The router moves on to sign-in.
  void _done() {
    ref.invalidate(lodgingNameProvider);
    ref.read(setupStatusProvider.notifier).markDone();
  }

  Widget _field(
    SetupField field,
    String label, {
    bool obscure = false,
    bool last = false,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LabeledField(
      label: label,
      controller: _fields[field]!,
      fieldKey: ValueKey('setup.${field.name}'),
      obscureText: obscure,
      errorText: _errors[field],
      helperText: helper,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _submit() : null,
    ),
  );

  @override
  Widget build(BuildContext context) => SplitGateLayout(
    title: 'Set up this lodging',
    subtitle: "Create the supervisor's account. You can add receptionists afterwards.",
    children: [
      _field(
        SetupField.lodgingName,
        'Lodging name',
        helper: 'Printed at the top of every receipt',
      ),
      _field(SetupField.fullName, 'Your full name'),
      _field(SetupField.username, 'Username'),
      _field(
        SetupField.password,
        'Password',
        obscure: true,
        helper: 'At least 8 characters',
      ),
      _field(
        SetupField.confirmPassword,
        'Confirm password',
        obscure: true,
        last: true,
      ),
      if (_formError != null) ...[Note.error(_formError!), formGap],
      AppButton.primary(
        key: const ValueKey('setup.submit'),
        label: 'Create supervisor account',
        large: true,
        busy: _busy,
        onPressed: _submit,
      ),
    ],
  );
}
