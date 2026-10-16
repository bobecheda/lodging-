import 'package:flutter/material.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/user_account.dart';
import '../../../auth/domain/credentials.dart';

/// Asks for a temporary password; pops it, or null on Cancel.
class ResetPasswordDialog extends StatefulWidget {
  const ResetPasswordDialog({super.key, required this.user});

  final UserAccount user;

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = passwordError(_password.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      title: Text(
        'Reset ${widget.user.fullName}’s password',
        style: t.sectionTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Temporary password',
              controller: _password,
              fieldKey: const ValueKey('reset.password'),
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.x12),
            Text(
              'They choose their own password the next time they sign in.',
              style: t.small,
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('reset.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.primary(
          key: const ValueKey('reset.ok'),
          label: 'Reset password',
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Confirms disabling [user], with [warning] when their shift is open.
/// Pops true on Disable.
class DisableUserDialog extends StatelessWidget {
  const DisableUserDialog({super.key, required this.user, this.warning});

  final UserAccount user;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      title: Text('Disable ${user.fullName}?', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'They won’t be able to sign in until you enable the account '
              'again.',
              style: t.body,
            ),
            if (warning != null) ...[
              const SizedBox(height: Space.x16),
              Note.warning(warning!, key: const ValueKey('disable.warning')),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('disable.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.destructive(
          key: const ValueKey('disable.ok'),
          label: 'Disable',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
