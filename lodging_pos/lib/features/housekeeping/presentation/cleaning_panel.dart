import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/bed_panel_frame.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_dropdown.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/side_panel.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../setup/domain/rooms.dart';
import '../data/housekeeping_repository.dart';
import '../domain/housekeeping.dart';
import 'housekeeping_providers.dart';

/// Opens the cleaning panel for a To clean bed (FD-9).
Future<void> showCleaningPanel(BuildContext context, String bedId) =>
    showSidePanel(
      context,
      barrierLabel: 'Close the cleaning panel',
      child: CleaningPanel(key: ValueKey('cleaning.$bedId'), bedId: bedId),
    );

/// FD-9, the bed panel's "To clean" state (v2 PR 5, Figma "Bed panel ·
/// states"): give the bed to a housekeeper, then mark it clean; or, if it's
/// already done, both at once (Mark clean). BR-9: only a finished cleaning
/// task makes a bed clean.
class CleaningPanel extends ConsumerStatefulWidget {
  const CleaningPanel({super.key, required this.bedId});

  final String bedId;

  @override
  ConsumerState<CleaningPanel> createState() => _CleaningPanelState();
}

class _CleaningPanelState extends ConsumerState<CleaningPanel> {
  String? _housekeeper;
  var _reassigning = false;
  var _busy = false;
  String? _problem;
  var _cleaned = false;

  Future<void> _run(
    Future<void> Function() action, {
    bool cleans = false,
  }) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _reassigning = false;
        _housekeeper = null;
        if (cleans) _cleaned = true;
      });
    } on HousekeepingRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t do this.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final bed = ref.watch(bedCleaningProvider(widget.bedId)).value;
    final housekeepers = ref.watch(activeHousekeepersProvider).value;
    if (user == null || bed == null || housekeepers == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final repo = ref.read(housekeepingRepositoryProvider);
    final names = housekeeperNames(housekeepers);
    final canAssign = can(user, Permission.assignHousekeeping);
    final canClean = can(user, Permission.markClean);
    final task = bed.openTask;
    final now = ref.watch(clockProvider).now();
    void close() => Navigator.of(context).pop();
    final clean = _cleaned || bed.cleanliness == Cleanliness.clean;

    Widget picker(Iterable<HousekeeperOption> choices) =>
        LabeledDropdown<String>(
          fieldKey: const ValueKey('cleaning.housekeeper'),
          label: 'Housekeeper',
          options: [
            for (final h in choices) DropdownOption(h.id, names[h.id]!),
          ],
          value: _housekeeper,
          onChanged: (id) => setState(() => _housekeeper = id),
        );

    final List<Widget> body;
    final List<Widget> actions;
    if (clean) {
      body = [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                'Clean and ready to let',
                key: const ValueKey('cleaning.done'),
                style: t.sectionTitle,
              ),
            ),
          ],
        ),
      ];
      actions = [
        AppButton.secondary(
          key: const ValueKey('cleaning.close'),
          label: 'Done',
          onPressed: close,
        ),
      ];
    } else {
      final chosen = _housekeeper;
      body = [
        PanelBanner(
          key: const ValueKey('cleaning.banner'),
          icon: LucideIcons.clock,
          tone: BannerTone.butter,
          text: switch (bed.lastCheckoutAt) {
            final DateTime at when formatDayDate(at) == formatDayDate(now) =>
              'Checked out today ${formatTime(at)}',
            final DateTime at => 'Checked out ${formatDayDateComma(at)}',
            null => 'Not cleaned since it was opened.',
          },
        ),
        const SizedBox(height: Space.x16),
        if (task != null && !_reassigning)
          Text(
            '${task.housekeeperName} · assigned '
            '${formatTime(task.assignedAt)}',
            key: const ValueKey('cleaning.assignee'),
            style: t.sectionTitle,
          )
        else if (task != null)
          picker(housekeepers.where((h) => h.id != task.housekeeperId))
        else if (housekeepers.isEmpty)
          const Note.info(
            'No housekeepers yet. The supervisor adds them in Setup → Users & '
            'staff.',
            key: ValueKey('cleaning.noHousekeepers'),
          )
        else
          picker(housekeepers),
        if (_problem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_problem!, key: const ValueKey('cleaning.problem')),
        ],
      ];
      actions = [
        if (task != null && !_reassigning) ...[
          AppButton.primary(
            key: const ValueKey('cleaning.markClean'),
            label: 'Mark clean',
            busy: _busy,
            onPressed: canClean
                ? () =>
                      _run(() => repo.markClean(user, bed.bedId), cleans: true)
                : null,
          ),
          const SizedBox(height: Space.x10),
          AppButton.secondary(
            key: const ValueKey('cleaning.reassign'),
            label: 'Reassign',
            onPressed: canAssign && housekeepers.length > 1
                ? () => setState(() => _reassigning = true)
                : null,
          ),
        ] else if (task != null) ...[
          AppButton.primary(
            key: const ValueKey('cleaning.reassignSave'),
            label: chosen == null ? 'Reassign' : 'Reassign to ${names[chosen]}',
            busy: _busy,
            onPressed: chosen == null
                ? null
                : () => _run(() => repo.reassign(user, bed.bedId, chosen)),
          ),
          const SizedBox(height: Space.x10),
          AppButton.secondary(
            key: const ValueKey('cleaning.reassignCancel'),
            label: 'Cancel',
            onPressed: () => setState(() {
              _reassigning = false;
              _housekeeper = null;
            }),
          ),
        ] else if (housekeepers.isNotEmpty) ...[
          AppButton.primary(
            key: const ValueKey('cleaning.assign'),
            label: 'Assign cleaning',
            busy: _busy,
            onPressed: chosen == null || !canAssign
                ? null
                : () => _run(() => repo.assign(user, bed.bedId, chosen)),
          ),
          const SizedBox(height: Space.x10),
          // Already cleaned: assigned and marked clean at once.
          AppButton.secondary(
            key: const ValueKey('cleaning.cleanNow'),
            label: 'Mark clean',
            onPressed: chosen == null || !canAssign || !canClean || _busy
                ? null
                : () => _run(
                    () => repo.cleanNow(user, bed.bedId, chosen),
                    cleans: true,
                  ),
          ),
        ],
      ];
    }

    return BedPanelFrame(
      head: BedPanelHead(
        roomNumber: bed.roomNumber,
        bedLabel: bed.label.code,
        subtitle:
            '${bed.categoryName} · ${formatKes(bed.pricePerNight)} a night',
        colourKey: bed.categoryColour,
        status: clean ? BedPanelStatus.ready : BedPanelStatus.toClean,
        onClose: close,
        titleKey: const ValueKey('cleaning.title'),
        closeKey: const ValueKey('cleaning.closeIcon'),
      ),
      body: body,
      actions: actions,
    );
  }
}
