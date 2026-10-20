import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../data/backup_service.dart';
import '../domain/backup.dart';
import 'backup_providers.dart';

/// "Backups" in Prices and settings ([Permission.manageBackups]): the last
/// backup, its folder, Back up now, and the optional second folder (e.g. a
/// USB drive). Shown only on the desk, where backups run.
class BackupsCard extends ConsumerStatefulWidget {
  const BackupsCard({super.key});

  @override
  ConsumerState<BackupsCard> createState() => _BackupsCardState();
}

class _BackupsCardState extends ConsumerState<BackupsCard> {
  String? _problem;

  Backups get _backups => ref.read(backupsProvider.notifier);

  Future<void> _backUpNow() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _problem = null);
    try {
      await _backups.backUpNow(user);
    } on BackupFailed {
      // The card shows the failure from the status.
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'Only the owner can back up.');
    }
  }

  Future<void> _chooseSecond() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    final path = await ref.read(backupShellProvider).pickFolder();
    if (path == null || !mounted) return;
    await _setSecond(path);
  }

  Future<void> _setSecond(String? path) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _problem = null);
    try {
      await _backups.setSecondFolder(user, path);
    } on NotPermitted {
      if (mounted) {
        setState(() => _problem = 'Only the owner can change the folders.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final status = ref.watch(backupsProvider);
    final now = ref.watch(clockProvider).now();
    final newest = status.newest;
    final shell = ref.read(backupShellProvider);

    Widget label(String text) => Text(text, style: t.fieldLabel);
    Widget path(String text, String key) => Text(
      text,
      key: ValueKey(key),
      style: t.mono.copyWith(color: c.inkSoft),
    );

    final Widget last;
    if (status.running) {
      last = Text(
        'Backing up…',
        key: const ValueKey('backups.last'),
        style: t.body,
      );
    } else if (newest != null) {
      last = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Last backup ', style: t.body),
            TextSpan(
              text: formatBackupWhen(newest.takenAt, now),
              style: t.bodyStrong,
            ),
            TextSpan(
              text: ' · ${formatBackupSize(newest.sizeBytes)} · checked',
              style: t.body,
            ),
          ],
        ),
        key: const ValueKey('backups.last'),
      );
    } else {
      last = Text(
        'No backup yet.',
        key: const ValueKey('backups.last'),
        style: t.body,
      );
    }

    final second = status.secondFolder;
    final secondNote = switch (status.second) {
      null => null,
      SecondCopied() => 'Copied with the last backup.',
      SecondSkipped() =>
        'Second copy skipped: USB drive not found. Main backup OK.',
      SecondFailed(:final message) =>
        'Second copy failed: $message. Main backup OK.',
    };

    return Card(
      key: const ValueKey('backups.card'),
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Backups', style: t.sectionTitle),
            ),
            const SizedBox(height: Space.x4),
            Text(
              'Every day, after each shift close and when you ask. Each copy '
              'is checked before it counts. Kept 30 days.',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x16),
            last,
            if (status.lastFailure case final failure?) ...[
              const SizedBox(height: Space.x12),
              Note.error(
                failure,
                key: const ValueKey('backups.failed'),
                title: 'The last backup failed.',
              ),
            ],
            const SizedBox(height: Space.x16),
            label('Folder'),
            const SizedBox(height: Space.x4),
            if (status.folder case final folder?)
              path(folder, 'backups.folder'),
            const SizedBox(height: Space.x12),
            Wrap(
              spacing: Space.x12,
              runSpacing: Space.x8,
              children: [
                AppButton.primary(
                  key: const ValueKey('backups.now'),
                  label: 'Back up now',
                  busy: status.running,
                  onPressed: _backUpNow,
                ),
                if (status.folder case final folder?)
                  AppButton.secondary(
                    key: const ValueKey('backups.openFolder'),
                    label: 'Open folder',
                    onPressed: () => shell.openFolder(folder),
                  ),
              ],
            ),
            if (_problem != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_problem!, key: const ValueKey('backups.problem')),
            ],
            const SizedBox(height: Space.x20),
            Divider(color: c.lineSoft),
            const SizedBox(height: Space.x12),
            label('Second copy'),
            const SizedBox(height: Space.x4),
            Text(
              'A USB drive or external disk, so a copy survives if this PC '
              'fails.',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x8),
            if (second == null)
              Text(
                'Not set.',
                key: const ValueKey('backups.second.none'),
                style: t.body,
              )
            else
              path(second, 'backups.second.folder'),
            if (secondNote != null) ...[
              const SizedBox(height: Space.x6),
              Text(
                secondNote,
                key: const ValueKey('backups.second.note'),
                style: t.small.copyWith(color: c.inkSoft),
              ),
            ],
            const SizedBox(height: Space.x12),
            Wrap(
              spacing: Space.x12,
              runSpacing: Space.x8,
              children: [
                AppButton.secondary(
                  key: const ValueKey('backups.second.choose'),
                  label: second == null ? 'Choose folder' : 'Change',
                  onPressed: _chooseSecond,
                ),
                if (second != null)
                  AppButton.secondary(
                    key: const ValueKey('backups.second.remove'),
                    label: 'Remove',
                    onPressed: () => _setSecond(null),
                  ),
              ],
            ),
            if (second != null) ...[
              const SizedBox(height: Space.x12),
              Text(
                'This drive holds guests’ phones and ID numbers. Keep it '
                'locked away.',
                key: const ValueKey('backups.second.privacy'),
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
