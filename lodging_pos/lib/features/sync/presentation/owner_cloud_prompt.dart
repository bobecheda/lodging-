import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../core/sync/cloud.dart';
import '../../../core/sync/cloud_writes.dart';
import '../../../core/sync/sync_providers.dart';

/// Before an owner write that goes to the cloud first: if this desk is
/// connected and the owner isn't signed in to the cloud, asks for the
/// password now (before the screen shows itself busy). False if the owner
/// cancelled.
Future<bool> ensureOwnerCloud(BuildContext context, WidgetRef ref) async {
  final engine = ref.read(syncEngineProvider);
  if (engine == null || !engine.active || engine.ownerCloudSignedIn) {
    return true;
  }
  final signedIn = await showDialog<bool>(
    context: context,
    builder: (_) => const OwnerCloudSignInDialog(),
  );
  return signedIn == true;
}

/// Runs [action] (an owner write that goes to the cloud first). When the
/// owner's cloud sign-in is missing (signed in on the desk offline, or it
/// lapsed), asks for the password once and runs it again. Returns false if
/// the owner cancelled.
Future<bool> withOwnerCloud(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on OwnerCloudSignInNeeded {
    if (!context.mounted) return false;
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (_) => const OwnerCloudSignInDialog(),
    );
    if (signedIn != true) return false;
    await action();
    return true;
  }
}

/// "Sign in to the cloud": the owner's desk password, for the cloud writes
/// of this session.
class OwnerCloudSignInDialog extends ConsumerStatefulWidget {
  const OwnerCloudSignInDialog({super.key});

  @override
  ConsumerState<OwnerCloudSignInDialog> createState() =>
      _OwnerCloudSignInDialogState();
}

class _OwnerCloudSignInDialogState
    extends ConsumerState<OwnerCloudSignInDialog> {
  final _password = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await engine.signInOwner(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on NeedsInternet {
      if (mounted) setState(() => _error = 'No internet connection.');
    } on CloudSignInRefused {
      if (mounted) setState(() => _error = 'Wrong password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      key: const ValueKey('ownerCloud.dialog'),
      title: Text('Sign in to the cloud', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Decisions and prices go to the cloud first, so your phone and '
              'this desk agree. Enter your password once for this session.',
              style: t.small,
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'Password',
              controller: _password,
              fieldKey: const ValueKey('ownerCloud.password'),
              errorText: _error,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('ownerCloud.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          key: const ValueKey('ownerCloud.signIn'),
          label: 'Sign in',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
