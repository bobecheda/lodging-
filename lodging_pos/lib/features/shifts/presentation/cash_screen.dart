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
import '../../sync/presentation/owner_cloud_prompt.dart';
import '../data/shift_repository.dart';
import '../domain/cash_review.dart';
import '../domain/drawer.dart';
import '../domain/shift_close.dart';
import 'shift_providers.dart';

/// Story B "Cash" (supervisor and owner, `viewShiftTotals`): what the drawer
/// should hold now, and its chain, newest first: the starting cash, each
/// shift's opening (its float checked against the count before it) and
/// close. Any gap points to one shift. Before the first shift, the
/// supervisor or owner counts the starting cash here (`checkDrawer`).
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final chain = ref.watch(drawerChainProvider);
    final now = ref.watch(drawerNowProvider).value;
    final started = ref.watch(drawerStartedProvider).value;

    final Widget list = switch (chain) {
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'The drawer could not be loaded.',
      ),
      AsyncData(:final value) when value.isEmpty => Text(
        'Nothing yet. The chain starts with the starting cash.',
        style: t.secondary,
      ),
      AsyncData(:final value) => ListView.separated(
        key: const ValueKey('cash.chain'),
        itemCount: value.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.x8),
        itemBuilder: (context, i) => _EntryTile(value[i]),
      ),
      _ => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Cash', style: t.pageTitle)),
        Text(
          'The drawer’s running ledger. A float that isn’t the count before '
          'it is a break in the chain.',
          style: t.secondary.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.x20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'The drawer should hold now',
                              style: t.secondary.copyWith(color: c.muted),
                            ),
                            const SizedBox(height: Space.x4),
                            Text(
                              now == null ? 'Not counted yet' : formatKes(now),
                              key: const ValueKey('cash.now'),
                              style: t.money,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (started == false &&
                        user != null &&
                        can(user, Permission.checkDrawer)) ...[
                      const SizedBox(height: Space.x16),
                      const _StartCard(),
                    ],
                    if (started == true && user != null) ...[
                      if (can(user, Permission.checkDrawer)) ...[
                        const SizedBox(height: Space.x16),
                        AppButton.secondary(
                          key: const ValueKey('cash.check'),
                          label: 'Check the drawer',
                          icon: Icons.fact_check_outlined,
                          onPressed: () => context.go(
                            Routes.drawerCountFor(DrawerCountKind.check.code),
                          ),
                        ),
                      ],
                      if (can(user, Permission.collectCash)) ...[
                        const SizedBox(height: Space.x8),
                        AppButton.secondary(
                          key: const ValueKey('cash.collect'),
                          label: 'Collect cash',
                          icon: Icons.savings_outlined,
                          onPressed: () => context.go(
                            Routes.drawerCountFor(DrawerCountKind.collect.code),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.x24),
              Expanded(child: list),
            ],
          ),
        ),
      ],
    );
  }
}

/// Counting the starting cash, once, before the first shift
/// (`drawer.start`).
class _StartCard extends ConsumerStatefulWidget {
  const _StartCard();

  @override
  ConsumerState<_StartCard> createState() => _StartCardState();
}

class _StartCardState extends ConsumerState<_StartCard> {
  final _count = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(sessionProvider);
    final amount = parseKes(_count.text);
    final problem = countError(amount);
    setState(() => _error = problem);
    if (user == null || problem != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(shiftRepositoryProvider)
          .startDrawer(user, counted: amount!);
      ref.invalidate(drawerStartedProvider);
    } on DrawerRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t count the drawer.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Card(
      key: const ValueKey('cash.startCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Starting cash', style: t.sectionTitle),
            const SizedBox(height: Space.x4),
            Text(
              'Count all the cash in the drawer on the day, before the first '
              'shift. Every float follows from it.',
              style: t.secondary,
            ),
            const SizedBox(height: Space.x12),
            MoneyInput(
              label: 'Cash counted',
              controller: _count,
              fieldKey: const ValueKey('cash.startCount'),
              errorText: _error,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: Space.x12),
            AppButton.primary(
              key: const ValueKey('cash.startSave'),
              label: 'Save the starting cash',
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry);

  final ChainEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final e = entry;
    final flagged = switch (e) {
      ShiftOpenedEntry(:final isBreak) => isBreak,
      ShiftClosedEntry(:final needsReview) => needsReview,
      DrawerCountEntry(:final needsReview) => needsReview,
      DrawerStarted() => false,
    };
    final key = switch (e) {
      ShiftOpenedEntry(:final shiftId) => 'cash.open.$shiftId',
      ShiftClosedEntry(:final shiftId) => 'cash.close.$shiftId',
      DrawerChecked(:final record) => 'cash.check.${record.id}',
      CashCollected(:final record) => 'cash.collect.${record.id}',
      DrawerStarted() => 'cash.start',
    };
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.all(Space.x12),
      decoration: BoxDecoration(
        color: flagged ? c.butter : c.white,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: flagged ? c.butterBorder : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.title, style: t.bodyMedium)),
              Text(
                formatDayDateTime(e.at),
                style: t.secondary.copyWith(color: c.muted),
              ),
            ],
          ),
          Text(e.detail, style: t.secondary.copyWith(color: c.inkSoft)),
          if (e is ShiftOpenedEntry && e.isBreak)
            Text(
              'Break in the chain.',
              style: t.meta.copyWith(color: c.butterText),
            ),
          if (e is DrawerCountEntry && e.needsReview)
            _ReviewBox(ReviewTargetKind.drawerEvent, e.record.id),
          if (e is ShiftClosedEntry && e.needsReview)
            _ReviewBox(ReviewTargetKind.shift, e.shiftId),
          if (e is DrawerCountEntry) ...[
            if (recountLine(e.record.firstCount, e.record.counted)
                case final line?)
              Text(line, style: t.secondary.copyWith(color: c.muted)),
            if (e.matchedOnRecount)
              Text('Matched only on recount.', style: t.secondary),
            if (e.needsReview)
              Text(
                'Needs review.',
                style: t.meta.copyWith(color: c.butterText),
              ),
            if (e.note case final note?)
              Text('“$note”', style: t.secondary.copyWith(color: c.inkSoft)),
          ],
          if (e is ShiftClosedEntry) ...[
            if (recountLine(e.firstCount, e.counted) case final line?)
              Text(line, style: t.secondary.copyWith(color: c.muted)),
            if (e.matchedOnRecount)
              Text('Matched only on recount.', style: t.secondary),
            if (e.needsReview)
              Text(
                'Needs review.',
                style: t.meta.copyWith(color: c.butterText),
              ),
            if (e.note case final note?)
              Text('“$note”', style: t.secondary.copyWith(color: c.inkSoft)),
          ],
        ],
      ),
    );
  }
}

/// A close or count that needs review (Story B3): its status, and Approve
/// or Reject for someone who may decide it, or why they can't.
class _ReviewBox extends ConsumerStatefulWidget {
  const _ReviewBox(this.kind, this.id);

  final ReviewTargetKind kind;
  final String id;

  @override
  ConsumerState<_ReviewBox> createState() => _ReviewBoxState();
}

class _ReviewBoxState extends ConsumerState<_ReviewBox> {
  String? _error;
  var _busy = false;

  Future<void> _decide({required bool approve}) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectReviewDialog(),
      );
      if (reason == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await withOwnerCloud(
        context,
        ref,
        () => ref
            .read(cashReviewsRepositoryProvider)
            .decide(
              user,
              widget.kind,
              widget.id,
              approve: approve,
              reason: reason,
            ),
      );
      ref.invalidate(reviewPanelProvider(widget.kind, widget.id));
    } on CashReviewProblem catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t review cash.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final panel = ref.watch(reviewPanelProvider(widget.kind, widget.id)).value;
    if (user == null || panel == null) return const SizedBox.shrink();
    final (target, info) = panel;
    final key = '${widget.kind.code}.${widget.id}';
    if (info != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.x4),
        child: Text(
          info.line,
          key: ValueKey('review.decided.$key'),
          style: t.meta.copyWith(
            color: info.decision == ReviewDecision.rejected
                ? c.redText
                : c.marine,
          ),
        ),
      );
    }
    final blocker = target == null ? null : reviewBlocker(target, user);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocker != null)
            Text(
              blocker,
              key: ValueKey('review.blocked.$key'),
              style: t.secondary.copyWith(color: c.inkSoft),
            )
          else
            Row(
              children: [
                AppButton.primary(
                  key: ValueKey('review.approve.$key'),
                  label: 'Approve',
                  compact: true,
                  busy: _busy,
                  onPressed: _busy ? null : () => _decide(approve: true),
                ),
                const SizedBox(width: Space.x8),
                AppButton.secondary(
                  key: ValueKey('review.reject.$key'),
                  label: 'Reject…',
                  compact: true,
                  onPressed: _busy ? null : () => _decide(approve: false),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: Space.x4),
            Note.error(_error!, key: ValueKey('review.error.$key')),
          ],
        ],
      ),
    );
  }
}

class _RejectReviewDialog extends StatefulWidget {
  const _RejectReviewDialog();

  @override
  State<_RejectReviewDialog> createState() => _RejectReviewDialogState();
}

class _RejectReviewDialogState extends State<_RejectReviewDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final r = _reason.text.trim();
    if (r.isEmpty) {
      setState(() => _error = 'Say why you reject it.');
      return;
    }
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      key: const ValueKey('review.rejectDialog'),
      title: Text('Reject this?', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: LabeledField(
          label: 'Reason',
          controller: _reason,
          fieldKey: const ValueKey('review.reason'),
          errorText: _error,
          autofocus: true,
          helperText: 'The owner sees it.',
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('review.reason.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.destructive(
          key: const ValueKey('review.reason.reject'),
          label: 'Reject',
          onPressed: _submit,
        ),
      ],
    );
  }
}
