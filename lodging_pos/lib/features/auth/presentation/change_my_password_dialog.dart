import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/session.dart';
import '../data/owner_password_service.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';

/// "Change my password" for the owner, from the sidebar (owner-app-3). The
/// password is also the owner's cloud sign-in, so once the desk is
/// connected it changes in the cloud first; offline it is refused. Pops
/// true once changed.
class ChangeMyPasswordDialog extends ConsumerStatefulWidget {
  const ChangeMyPasswordDialog({super.key});

  @override
  ConsumerState<ChangeMyPasswordDialog> createState() =>
      _ChangeMyPasswordState();
}

class _ChangeMyPasswordState extends ConsumerState<ChangeMyPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    if (_next.text != _repeat.text) {
      setState(() => _problem = 'The new passwords don’t match.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref
          .read(ownerPasswordServiceProvider)
          .change(user, current: _current.text, next: _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } on PasswordChangeRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return AlertDialog(
      key: const ValueKey('myPassword.dialog'),
      title: Text('Change my password', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.formMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'It is also your sign-in on the phone, so it changes there too '
              '(needs internet).',
              style: t.small.copyWith(color: c.inkSoft),
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'Current password',
              controller: _current,
              fieldKey: const ValueKey('myPassword.current'),
              obscureText: true,
              autofocus: true,
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'New password',
              controller: _next,
              fieldKey: const ValueKey('myPassword.new'),
              obscureText: true,
              helperText: 'At least $minPasswordLength characters',
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'New password again',
              controller: _repeat,
              fieldKey: const ValueKey('myPassword.repeat'),
              obscureText: true,
              onSubmitted: (_) => _save(),
            ),
            if (_problem != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_problem!, key: const ValueKey('myPassword.problem')),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('myPassword.cancel'),
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          key: const ValueKey('myPassword.save'),
          label: 'Change password',
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
