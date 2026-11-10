import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../data/shift_repository.dart';
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
        style: t.small,
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
          style: t.small.copyWith(color: c.muted),
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
                              style: t.small.copyWith(color: c.muted),
                            ),
                            const SizedBox(height: Space.x4),
                            Text(
                              now == null ? 'Not counted yet' : formatKes(now),
                              key: const ValueKey('cash.now'),
                              style: t.moneyLarge,
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
              style: t.small,
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
      DrawerStarted() => false,
    };
    final key = switch (e) {
      ShiftOpenedEntry(:final shiftId) => 'cash.open.$shiftId',
      ShiftClosedEntry(:final shiftId) => 'cash.close.$shiftId',
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
              Expanded(child: Text(e.title, style: t.bodyStrong)),
              Text(
                formatDayDateTime(e.at),
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ),
          Text(e.detail, style: t.small.copyWith(color: c.inkSoft)),
          if (e is ShiftOpenedEntry && e.isBreak)
            Text(
              'Break in the chain.',
              style: t.smallStrong.copyWith(color: c.butterText),
            ),
          if (e is ShiftClosedEntry) ...[
            if (recountLine(e.firstCount, e.counted) case final line?)
              Text(line, style: t.small.copyWith(color: c.muted)),
            if (e.matchedOnRecount)
              Text('Matched only on recount.', style: t.small),
            if (e.needsReview)
              Text(
                'Needs review.',
                style: t.smallStrong.copyWith(color: c.butterText),
              ),
            if (e.note case final note?)
              Text('“$note”', style: t.small.copyWith(color: c.inkSoft)),
          ],
        ],
      ),
    );
  }
}
