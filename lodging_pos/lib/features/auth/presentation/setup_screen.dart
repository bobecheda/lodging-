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

/// First run: creates the owner's account and names the lodging; the owner
/// then adds the supervisor. On a database from before the owner role, the
/// same screen asks only for the owner's account, before anyone may sign in
/// ([SetupState.needsOwner]). Unreachable once the owner exists (see the
/// router).
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

  /// Only the owner's account is missing: the lodging is already named.
  bool get _ownerOnly =>
      ref.read(setupStatusProvider).value == SetupState.needsOwner;

  Future<void> _submit() async {
    final ownerOnly = _ownerOnly;
    final errors = validateSetup(_input, withLodgingName: !ownerOnly);
    setState(() {
      _errors = errors;
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      final users = ref.read(userRepositoryProvider);
      if (ownerOnly) {
        await users.createMissingOwner(_input);
      } else {
        await users.createFirstOwner(_input);
      }
      _done();
    } on SetupAlreadyDone {
      _done();
    } on UsernameTaken catch (e) {
      if (mounted) {
        setState(() => _errors = {SetupField.username: e.toString()});
      }
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
  Widget build(BuildContext context) {
    final ownerOnly =
        ref.watch(setupStatusProvider).value == SetupState.needsOwner;
    return SplitGateLayout(
      title: ownerOnly ? "Create the owner's account" : 'Set up this lodging',
      subtitle: ownerOnly
          ? 'This lodging now has an owner above the supervisor. The owner '
                'sets prices, approves refunds and adds supervisors. Nobody '
                'can sign in until the owner\'s account exists.'
          : "Create the owner's account. You then add the supervisor, who "
                'adds receptionists.',
      children: [
        if (!ownerOnly)
          _field(
            SetupField.lodgingName,
            'Lodging name',
            helper: 'Printed at the top of every receipt',
          ),
        _field(SetupField.fullName, "Owner's full name"),
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
          label: 'Create owner account',
          large: true,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
