import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../backup/presentation/backup_providers.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';
import '../domain/shift_close.dart';
import '../domain/shift_rules.dart';
import 'shift_providers.dart';

enum _Step { count, review, done }

/// FD-11 "Close shift": a blind cash count, then the review (expected,
/// counted, variance, M-Pesa), a note when it's short or over, and Close
/// or Recount. Your own shift ends with Sign out; the owner closing
/// someone else's goes back to Shifts.
class CloseShiftScreen extends ConsumerStatefulWidget {
  const CloseShiftScreen({super.key, this.shiftId});

  /// Someone else's shift (`?shift=`); null closes your own.
  final String? shiftId;

  @override
  ConsumerState<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  final _count = TextEditingController();
  final _note = TextEditingController();
  var _step = _Step.count;
  int? _firstCount;
  int? _counted;
  ShiftTakings? _takings;
  CloseFigures? _closed;
  String? _countError;
  String? _noteError;
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _review(OpenShift shift) async {
    final amount = parseKes(_count.text);
    final problem = countError(amount);
    setState(() => _countError = problem);
    if (problem != null) return;
    final takings = await ref.read(shiftRepositoryProvider).takings(shift.id);
    if (!mounted) return;
    setState(() {
      _firstCount ??= amount;
      _counted = amount;
      _takings = takings;
      _problem = null;
      _step = _Step.review;
    });
  }

  void _recount() => setState(() {
    _count.clear();
    _noteError = null;
    _problem = null;
    _step = _Step.count;
  });

  Future<void> _close(OpenShift shift) async {
    final user = ref.read(sessionProvider);
    final takings = _takings;
    if (user == null || takings == null) return;
    final variance = closeFigures(
      takings,
      openingFloat: shift.openingFloat,
      firstCount: _firstCount!,
      counted: _counted!,
    ).variance;
    final noteProblem = closeNoteError(_note.text, variance);
    setState(() => _noteError = noteProblem);
    if (noteProblem != null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final figures = await ref
          .read(shiftRepositoryProvider)
          .closeShift(
            user,
            shift.id,
            firstCount: _firstCount!,
            counted: _counted!,
            note: _note.text,
            shown: takings,
          );
      // The day's takings go into a backup straight away, in the
      // background; the summary doesn't wait.
      ref.read(backupsProvider.notifier).afterShiftClose(user);
      if (!mounted) return;
      setState(() {
        _closed = figures;
        _step = _Step.done;
      });
      // Someone else's shift: the device is free now. (Your own is let go
      // on Sign out, so the gate doesn't take this screen away first.)
      if (shift.userId != user.id) ref.invalidate(currentShiftProvider);
    } on ShiftCloseRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t close this shift.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signOut() {
    ref.read(sessionProvider.notifier).signOut();
    ref.invalidate(currentShiftProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final c = LodgingColors.of(context);
    final user = ref.watch(sessionProvider);
    final id = widget.shiftId;
    final AsyncValue<OpenShift?> found = id == null
        ? ref.watch(currentShiftProvider)
        : ref.watch(openShiftByIdProvider(id));
    // Keep the shift being closed on screen after it's closed.
    final shift = _lastShift = found.value ?? _lastShift;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Close shift', style: t.pageTitle)),
        if (shift != null)
          Text(
            '${shift.userName} · shift since '
            '${formatDayDateTime(shift.openedAt)} · float '
            '${formatKes(shift.openingFloat)}',
            key: const ValueKey('closeShift.whose'),
            style: t.small.copyWith(color: c.muted),
          ),
      ],
    );

    final Widget body;
    if (user == null) {
      body = const SizedBox.shrink();
    } else if (shift == null ||
        (_step != _Step.done && id == null && shift.userId != user.id)) {
      body = const Note.info(
        'You have no open shift on this computer.',
        key: ValueKey('closeShift.none'),
      );
    } else {
      body = switch (_step) {
        _Step.count => _countStep(shift),
        _Step.review => _reviewStep(shift),
        _Step.done => _doneStep(shift, own: shift.userId == user.id),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: Space.x20),
        Expanded(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x24),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  OpenShift? _lastShift;

  Widget _countStep(OpenShift shift) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _firstCount == null
              ? 'Count the cash in the drawer, including the float.'
              : 'Count again. Your first count stays on the record.',
          style: t.body,
        ),
        const SizedBox(height: Space.x16),
        MoneyInput(
          label: 'Cash counted',
          controller: _count,
          fieldKey: const ValueKey('closeShift.count'),
          large: true,
          autofocus: true,
          errorText: _countError,
          helperText: 'Count first: what’s expected shows after.',
          onSubmitted: (_) => _review(shift),
        ),
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('closeShift.review'),
          label: 'Review',
          onPressed: () => _review(shift),
        ),
      ],
    );
  }

  Widget _reviewStep(OpenShift shift) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final takings = _takings!;
    final f = closeFigures(
      takings,
      openingFloat: shift.openingFloat,
      firstCount: _firstCount!,
      counted: _counted!,
    );
    final recount = recountLine(f.firstCount, f.counted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row('Opening float', formatKes(shift.openingFloat)),
        _Row('Cash taken', formatKes(takings.cash.received)),
        if (takings.cash.refunded > 0)
          _Row('Cash refunds paid', '− ${formatKes(takings.cash.refunded)}'),
        _Row(
          'Expected cash',
          formatKes(f.expectedCash),
          strong: true,
          valueKey: 'closeShift.expected',
        ),
        _Row(
          'Counted',
          formatKes(f.counted),
          strong: true,
          valueKey: 'closeShift.counted',
        ),
        if (recount != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x6),
            child: Text(
              recount,
              key: const ValueKey('closeShift.recountLine'),
              style: t.small.copyWith(color: c.muted),
            ),
          ),
        const SizedBox(height: Space.x6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusBadge(
            varianceLabel(f.variance).toUpperCase(),
            key: const ValueKey('closeShift.variance'),
            tone: f.variance == 0 ? BadgeTone.active : BadgeTone.warning,
          ),
        ),
        const SizedBox(height: Space.x12),
        Divider(color: c.lineSoft),
        _Row(
          'M-Pesa taken',
          formatKes(f.expectedPaybill),
          valueKey: 'closeShift.paybill',
        ),
        Text(
          'Compare this with the M-Pesa statement.',
          style: t.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x16),
        LabeledField(
          label: f.variance == 0 ? 'Note (optional)' : 'Note',
          controller: _note,
          fieldKey: const ValueKey('closeShift.note'),
          errorText: _noteError,
          helperText: f.variance == 0
              ? 'At most $closeNoteMax characters.'
              : 'Say why the cash is ${f.variance < 0 ? 'short' : 'over'}. '
                    'At most $closeNoteMax characters.',
        ),
        if (_problem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_problem!, key: const ValueKey('closeShift.problem')),
        ],
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('closeShift.confirm'),
          label: 'Close shift',
          busy: _busy,
          onPressed: () => _close(shift),
        ),
        const SizedBox(height: Space.x8),
        AppButton.secondary(
          key: const ValueKey('closeShift.recount'),
          label: 'Recount',
          onPressed: _busy ? null : _recount,
        ),
        const SizedBox(height: Space.x8),
        Text(
          'A closed shift can’t be reopened.',
          textAlign: TextAlign.center,
          style: t.small.copyWith(color: c.muted),
        ),
      ],
    );
  }

  Widget _doneStep(OpenShift shift, {required bool own}) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final f = _closed!;
    return Column(
      key: const ValueKey('closeShift.done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Text('Shift closed', style: t.sectionTitle),
          ],
        ),
        const SizedBox(height: Space.x16),
        _Row('Expected cash', formatKes(f.expectedCash)),
        _Row('Counted', formatKes(f.counted)),
        _Row('Variance', varianceLabel(f.variance), strong: true),
        _Row('M-Pesa taken', formatKes(f.expectedPaybill)),
        const SizedBox(height: Space.x20),
        if (own)
          AppButton.primary(
            key: const ValueKey('closeShift.signOut'),
            label: 'Sign out',
            onPressed: _signOut,
          )
        else
          AppButton.primary(
            key: const ValueKey('closeShift.backToShifts'),
            label: 'Back to Shifts',
            onPressed: () => context.go(Routes.shifts),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.strong = false, this.valueKey});

  final String label;
  final String value;
  final bool strong;
  final String? valueKey;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? t.bodyStrong : t.body).copyWith(
                color: strong ? c.ink : c.inkSoft,
              ),
            ),
          ),
          Text(
            value,
            key: switch (valueKey) {
              final String k => ValueKey<String>(k),
              null => null,
            },
            style: strong ? t.monoStrong : t.mono,
          ),
        ],
      ),
    );
  }
}
