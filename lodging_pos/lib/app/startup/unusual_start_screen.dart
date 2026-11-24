import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../theme/theme.dart';
import '../widgets/buttons.dart';
import '../widgets/labeled_field.dart';
import '../widgets/notes.dart';
import '../widgets/split_gate_layout.dart';
import 'startup_providers.dart';
import 'unusual_start.dart';

/// The desk runs from a removable drive or another folder than its install
/// folder (story/desk-db-guards): a warning before sign-in. The supervisor
/// or owner may carry on with their password; anyone else closes the app.
class UnusualStartScreen extends ConsumerStatefulWidget {
  const UnusualStartScreen({super.key});

  @override
  ConsumerState<UnusualStartScreen> createState() => _UnusualStartScreenState();
}

class _UnusualStartScreenState extends ConsumerState<UnusualStartScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _makeInstallFolder = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(unusualStartProvider.notifier)
          .accept(
            username: _username.text,
            password: _password.text,
            makeInstallFolder: _makeInstallFolder,
          );
    } on UnusualStartRefused catch (e) {
      _password.clear();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final location = ref.watch(unusualStartProvider);
    if (location == null) return const SizedBox.shrink();
    final why = location.removable
        ? 'The desk is running from a removable drive (${location.path}). '
              'A copy on a USB drive can open this PC’s data with an older '
              'version of the app.'
        : 'The desk is running from ${location.path}, not from the folder '
              'it was installed in (${location.recorded}). It may be an '
              'old copy.';
    return SplitGateLayout(
      title: 'Check where the desk runs from',
      subtitle:
          'Only the supervisor or the owner can carry on. Anyone else: '
          'close this window and start the desk from its usual shortcut.',
      showVersion: true,
      children: [
        Note.warning(why, key: const ValueKey('unusualStart.why')),
        formGap,
        Text(
          'This app: '
          '${versionLine(AppBuild.current, schemaVersion: latestSchemaVersion)}.',
          style: t.secondary,
        ),
        formGap,
        LabeledField(
          label: 'Supervisor or owner username',
          controller: _username,
          fieldKey: const ValueKey('unusualStart.username'),
          textInputAction: TextInputAction.next,
        ),
        formGap,
        LabeledField(
          label: 'Password',
          controller: _password,
          fieldKey: const ValueKey('unusualStart.password'),
          obscureText: true,
          onSubmitted: (_) => _accept(),
        ),
        if (!location.removable) ...[
          formGap,
          CheckboxListTile(
            key: const ValueKey('unusualStart.makeInstallFolder'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _makeInstallFolder,
            onChanged: (v) => setState(() => _makeInstallFolder = v ?? false),
            title: Text(
              'Make this the install folder from now on',
              style: t.body,
            ),
          ),
        ],
        formGap,
        if (_error != null) ...[Note.error(_error!), formGap],
        AppButton.primary(
          key: const ValueKey('unusualStart.accept'),
          label: 'Carry on from here',
          large: true,
          busy: _busy,
          onPressed: _accept,
        ),
      ],
    );
  }
}
