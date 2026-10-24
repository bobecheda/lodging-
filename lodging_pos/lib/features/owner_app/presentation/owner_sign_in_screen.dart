import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../data/owner_cloud.dart';
import 'owner_providers.dart';

/// The owner signs in with the email and password of their cloud account
/// (the desk's owner password). The phone stays signed in until Sign out.
class OwnerSignInScreen extends ConsumerStatefulWidget {
  const OwnerSignInScreen({super.key});

  @override
  ConsumerState<OwnerSignInScreen> createState() => _OwnerSignInState();
}

class _OwnerSignInState extends ConsumerState<OwnerSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _problem = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref
          .read(ownerSessionProvider.notifier)
          .signIn(email: _email.text, password: _password.text);
    } on OwnerSignInRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on OwnerCloudOffline {
      if (mounted) {
        setState(() => _problem = 'Signing in needs an internet connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final noCloud = ref.watch(ownerCloudProvider) == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sizes.formMaxWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Owner sign in', style: t.pageTitle),
                    ),
                    const SizedBox(height: Space.x6),
                    Text(
                      'Your email and the password you use at the desk.',
                      style: t.body.copyWith(color: c.inkSoft),
                    ),
                    const SizedBox(height: Space.x20),
                    if (noCloud) ...[
                      const Note.warning(
                        'This build has no cloud set up. Build it with '
                        'secrets.json.',
                        key: ValueKey('ownerSignIn.noCloud'),
                      ),
                      const SizedBox(height: Space.x16),
                    ],
                    LabeledField(
                      label: 'Email',
                      controller: _email,
                      fieldKey: const ValueKey('ownerSignIn.email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: Space.x12),
                    LabeledField(
                      label: 'Password',
                      controller: _password,
                      fieldKey: const ValueKey('ownerSignIn.password'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _signIn(),
                    ),
                    if (_problem != null) ...[
                      const SizedBox(height: Space.x12),
                      Note.error(
                        _problem!,
                        key: const ValueKey('ownerSignIn.problem'),
                      ),
                    ],
                    const SizedBox(height: Space.x20),
                    AppButton.primary(
                      key: const ValueKey('ownerSignIn.submit'),
                      label: 'Sign in',
                      large: true,
                      busy: _busy,
                      onPressed: noCloud ? null : _signIn,
                    ),
                    const SizedBox(height: Space.x16),
                    Text(
                      'Forgot your password? Ask whoever set up the cloud to '
                      'reset it.',
                      style: t.small.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
