import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/database/desk_startup.dart';
import '../../features/backup/data/restore_acceptance.dart';
import '../../features/backup/presentation/backup_providers.dart';
import '../theme/theme.dart';
import '../widgets/buttons.dart';
import '../widgets/labeled_field.dart';
import '../widgets/notes.dart';
import 'startup_providers.dart';

/// Shown instead of the app when the startup checks refuse the database
/// (story/desk-db-guards, docs/backup-restore.md "Startup checks"). The
/// database is never opened: nothing can write to it. Every refusal names
/// this app's version and the file's side.
class StartupRefusalScreen extends ConsumerStatefulWidget {
  const StartupRefusalScreen({
    super.key,
    required this.startup,
    required this.onRetry,
  });

  final DeskStartup startup;

  /// Runs the checks again (after the other copy closed, a restore, or an
  /// accepted backup).
  final Future<void> Function() onRetry;

  @override
  ConsumerState<StartupRefusalScreen> createState() =>
      _StartupRefusalScreenState();
}

class _StartupRefusalScreenState extends ConsumerState<StartupRefusalScreen> {
  final _password = TextEditingController();
  final _receipt = TextEditingController();
  final _email = TextEditingController();
  var _busy = false;
  String? _error;

  /// The restored file doesn't know the owner's cloud email.
  var _askEmail = false;

  @override
  void dispose() {
    _password.dispose();
    _receipt.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on RestoreRefused catch (e) {
      _password.clear();
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e is RestoreNeedsEmail) _askEmail = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptRestore(OlderThanBackup refused) => _run(() async {
    await ref
        .read(restoreAcceptanceProvider)
        .accept(
          refused,
          password: _password.text,
          lastPaperReceipt: _receipt.text,
          ownerEmail: _askEmail ? _email.text : null,
        );
    await widget.onRetry();
  });

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final verdict = widget.startup.verdict;
    final folder = widget.startup.folder;
    final (title, advice) = switch (verdict) {
      AlreadyOpen() => (
        'The desk is already open on this PC',
        'Close the other copy, then check again. Only one copy may use the '
            'desk’s data at a time.',
      ),
      DatabaseMissing() => (
        'Database missing — restore from backup',
        'Don’t start a new database: the lodging’s records are in the '
            'backups. The supervisor restores the newest backup as described '
            'in “Restore” (docs/backup-restore.md), then checks again.',
      ),
      NewerDatabase() || NewerBuild() => (
        'This app is older than the database',
        'Close this window and start the desk from its usual shortcut. Your '
            'data is untouched. Remove old copies of the app (USB drives, old '
            'folders).',
      ),
      OlderThanBackup() => (
        'This database looks older than the last backup',
        'Records may be missing. Nothing has been opened or changed. If '
            'this is a backup restored on purpose, only the owner can accept '
            'it. If the owner isn’t here, it waits.',
      ),
      StartOk() => ('', ''),
    };

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.x32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        key: const ValueKey('refusal.title'),
                        style: t.sectionTitle,
                      ),
                    ),
                    const SizedBox(height: Space.x12),
                    Text(advice, style: t.body),
                    const SizedBox(height: Space.x16),
                    Container(
                      padding: const EdgeInsets.all(Space.x12),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        refusalMessage(
                          verdict,
                          AppBuild.current,
                          schemaVersion: latestSchemaVersion,
                        ),
                        key: const ValueKey('refusal.details'),
                        style: t.secondary,
                      ),
                    ),
                    if (verdict is OlderThanBackup) ...[
                      const SizedBox(height: Space.x20),
                      Text(
                        'The owner accepts this backup',
                        style: t.bodyMedium,
                      ),
                      const SizedBox(height: Space.x12),
                      if (_askEmail) ...[
                        LabeledField(
                          label: 'Owner’s email',
                          controller: _email,
                          fieldKey: const ValueKey('refusal.email'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: Space.x16),
                      ],
                      LabeledField(
                        label: 'Owner’s password',
                        controller: _password,
                        fieldKey: const ValueKey('refusal.password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: Space.x16),
                      LabeledField(
                        label: 'Number on the last receipt printed',
                        hintText: 'e.g. R-000061',
                        controller: _receipt,
                        fieldKey: const ValueKey('refusal.lastReceipt'),
                      ),
                      const SizedBox(height: Space.x8),
                      Text(
                        'New receipts will start after it, so no number is '
                        'used twice.',
                        style: t.secondary.copyWith(color: c.muted),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: Space.x16),
                      Note.error(_error!),
                    ],
                    const SizedBox(height: Space.x20),
                    switch (verdict) {
                      final OlderThanBackup refused => AppButton.primary(
                        key: const ValueKey('refusal.acceptRestore'),
                        label: 'Use this backup',
                        busy: _busy,
                        onPressed: () => _acceptRestore(refused),
                      ),
                      AlreadyOpen() || DatabaseMissing() => AppButton.secondary(
                        key: const ValueKey('refusal.retry'),
                        label: 'Check again',
                        busy: _busy,
                        onPressed: () => _run(widget.onRetry),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                    if (verdict is DatabaseMissing && folder != null) ...[
                      const SizedBox(height: Space.x12),
                      AppButton.secondary(
                        key: const ValueKey('refusal.openFolder'),
                        label: 'Open the data folder',
                        onPressed: () =>
                            ref.read(backupShellProvider).openFolder(folder),
                      ),
                    ],
                    const SizedBox(height: Space.x20),
                    Text(
                      versionLine(
                        AppBuild.current,
                        schemaVersion: latestSchemaVersion,
                      ),
                      key: const ValueKey('refusal.version'),
                      textAlign: TextAlign.center,
                      style: t.meta.copyWith(color: c.muted),
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
