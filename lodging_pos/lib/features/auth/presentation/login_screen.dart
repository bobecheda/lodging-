import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/split_gate_layout.dart';
import '../../../core/auth/session.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../domain/login.dart';
import 'auth_providers.dart';
import 'idle_lock.dart';

/// Sign in, and the lock screen after an idle or manual lock. The username
/// always starts empty, so whoever sits down signs in as themselves.
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
            'This account is disabled. Ask the supervisor to enable it.',
          _ => 'Wrong username or password. Try again.',
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(idleLockProvider);
    final shiftOpen = ref.watch(currentShiftProvider).value != null;

    return SplitGateLayout(
      title: notice == null ? 'Sign in' : 'Screen locked',
      subtitle: notice == null
          ? 'Use the username and password the supervisor gave you.'
          : shiftOpen
          ? 'The open shift is kept. Sign in to carry on.'
          : 'Sign in to carry on.',
      above: notice == null ? null : _LockChip(notice),
      footer: 'Forgot your password? Ask the supervisor to reset it.',
      children: [
        LabeledField(
          label: 'Username',
          controller: _username,
          fieldKey: const ValueKey('login.username'),
          autofocus: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        formGap,
        LabeledField(
          label: 'Password',
          controller: _password,
          fieldKey: const ValueKey('login.password'),
          obscureText: true,
          onSubmitted: (_) => _submit(),
          autofillHints: const [AutofillHints.password],
        ),
        formGap,
        if (_error != null) ...[Note.error(_error!), formGap],
        AppButton.primary(
          key: const ValueKey('login.submit'),
          label: 'Sign in',
          large: true,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Butter chip saying why the screen locked.
class _LockChip extends StatelessWidget {
  const _LockChip(this.notice);

  final LockNotice notice;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final text = switch (notice) {
      IdleLockNotice(:final minutes) =>
        'Screen locked after $minutes minutes idle',
      ManualLockNotice() => 'Screen locked',
    };
    return Container(
      key: const ValueKey('login.lockChip'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x12,
        vertical: Space.x6,
      ),
      decoration: BoxDecoration(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: c.butterText),
          const SizedBox(width: Space.x6),
          Flexible(
            child: Text(
              text,
              style: t.smallStrong.copyWith(color: c.butterText),
            ),
          ),
        ],
      ),
    );
  }
}
