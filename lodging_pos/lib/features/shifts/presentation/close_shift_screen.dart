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
import 'shift_providers.dart';

/// FD-11 "Close shift", blind (Story B): count the cash; a count that
/// matches closes the shift. One that doesn't says so, with no amount and
/// no short or over, and asks for one recount; a recount that still doesn't
/// match asks why, and the shift closes anyway, for review. Each count is
/// saved before the next is asked for, so leaving and coming back never
/// gives another try. Only users with `viewShiftTotals` (supervisor, owner)
/// see any figure, and only once the shift is closed.
class CloseShiftScreen extends ConsumerStatefulWidget {
  const CloseShiftScreen({super.key, this.shiftId});

  /// Someone else's shift (`?shift=`); null closes your own.
  final String? shiftId;

  @override
  ConsumerState<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  final _count = TextEditingController();
  final _reason = TextEditingController();
  CloseFigures? _closed;
  var _needsReview = false;
  String? _countError;
  String? _reasonError;
  String? _problem;
  var _busy = false;
  OpenShift? _lastShift;

  @override
  void dispose() {
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
    } on ShiftCloseRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t close this shift.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _closedWith(
    OpenShift shift,
    CloseFigures figures, {
    bool review = false,
  }) {
    final user = ref.read(sessionProvider)!;
    // The day's takings go into a backup straight away, in the background.
    ref.read(backupsProvider.notifier).afterShiftClose(user);
    setState(() {
      _closed = figures;
      _needsReview = review;
    });
    // Someone else's shift: the device is free now. (Your own is let go on
    // Sign out, so the gate doesn't take this screen away first.)
    if (shift.userId != user.id) ref.invalidate(currentShiftProvider);
  }

  Future<void> _submitCount(OpenShift shift) async {
    final user = ref.read(sessionProvider);
    final amount = parseKes(_count.text);
    final problem = countError(amount);
    setState(() => _countError = problem);
    if (user == null || problem != null) return;
    await _run(() async {
      final result = await ref
          .read(shiftRepositoryProvider)
          .submitCount(user, shift.id, amount!);
      if (!mounted) return;
      _count.clear();
      switch (result) {
        case CountClosed(:final figures):
          _closedWith(shift, figures);
        case CountAgain() || ReasonNeeded():
          ref.invalidate(closeStageProvider(shift.id));
      }
    });
  }

  Future<void> _submitReason(OpenShift shift) async {
    final user = ref.read(sessionProvider);
    final problem = closeReasonError(_reason.text);
    setState(() => _reasonError = problem);
    if (user == null || problem != null) return;
    await _run(() async {
      final figures = await ref
          .read(shiftRepositoryProvider)
          .closeWithReason(user, shift.id, _reason.text);
      if (mounted) _closedWith(shift, figures, review: true);
    });
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
    final seesFigures = user != null && can(user, Permission.viewShiftTotals);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Close shift', style: t.pageTitle)),
        if (shift != null)
          Text(
            '${shift.userName} · shift since '
            '${formatDayDateTime(shift.openedAt)}',
            key: const ValueKey('closeShift.whose'),
            style: t.small.copyWith(color: c.muted),
          ),
      ],
    );

    final closed = _closed;
    final Widget body;
    if (user == null) {
      body = const SizedBox.shrink();
    } else if (closed != null && shift != null) {
      body = _doneStep(
        closed,
        own: shift.userId == user.id,
        seesFigures: seesFigures,
      );
    } else if (shift == null || (id == null && shift.userId != user.id)) {
      body = const Note.info(
        'You have no open shift on this computer.',
        key: ValueKey('closeShift.none'),
      );
    } else {
      body = switch (ref.watch(closeStageProvider(shift.id)).value) {
        null => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        CountStage.reason => _reasonStep(shift),
        final stage => _countStep(shift, recount: stage == CountStage.recount),
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

  Widget _countStep(OpenShift shift, {required bool recount}) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recount) ...[
          const Note.warning(
            countAgainMessage,
            key: ValueKey('closeShift.countAgain'),
          ),
          const SizedBox(height: Space.x16),
        ],
        Text(
          recount
              ? 'Count all the cash in the drawer once more. Your first '
                    'count stays on the record.'
              : 'Count all the cash in the drawer.',
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
          onSubmitted: (_) => _submitCount(shift),
        ),
        if (_problem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_problem!, key: const ValueKey('closeShift.problem')),
        ],
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('closeShift.submit'),
          label: recount ? 'Submit the recount' : 'Submit the count',
          busy: _busy,
          onPressed: () => _submitCount(shift),
        ),
        const SizedBox(height: Space.x8),
        Text(
          'A closed shift can’t be reopened.',
          textAlign: TextAlign.center,
          style: t.small,
        ),
      ],
    );
  }

  Widget _reasonStep(OpenShift shift) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Note.warning(
          reasonNeededMessage,
          key: ValueKey('closeShift.reasonNeeded'),
        ),
        const SizedBox(height: Space.x16),
        LabeledField(
          label: 'Reason',
          controller: _reason,
          fieldKey: const ValueKey('closeShift.reason'),
          errorText: _reasonError,
          autofocus: true,
          helperText:
              'The supervisor reviews it. At most $closeNoteMax characters.',
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
          onPressed: () => _submitReason(shift),
        ),
        const SizedBox(height: Space.x8),
        Text(
          'A closed shift can’t be reopened.',
          textAlign: TextAlign.center,
          style: t.small,
        ),
      ],
    );
  }

  Widget _doneStep(
    CloseFigures f, {
    required bool own,
    required bool seesFigures,
  }) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
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
        const SizedBox(height: Space.x8),
        Text(
          _needsReview
              ? 'Your count and your reason are recorded for review.'
              : 'Your count is recorded.',
          style: t.body.copyWith(color: c.inkSoft),
        ),
        if (seesFigures) ...[
          const SizedBox(height: Space.x16),
          _Row('Expected cash', formatKes(f.expectedCash)),
          _Row('Counted', formatKes(f.counted)),
          if (recountLine(f.firstCount, f.counted) case final line?)
            Text(line, style: t.small.copyWith(color: c.muted)),
          _Row(
            'Variance',
            varianceLabel(f.variance),
            strong: true,
            valueKey: 'closeShift.variance',
          ),
          _Row('M-Pesa taken', formatKes(f.expectedPaybill)),
        ],
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
