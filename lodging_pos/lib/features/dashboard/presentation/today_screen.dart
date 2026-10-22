import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../bed_board/presentation/bed_board_providers.dart';
import '../domain/dashboard.dart';
import 'dashboard_providers.dart';

/// The owner's Today on the desk (`viewBusinessDashboard`), matching the
/// phone design (Figma "01 Today"): Needs your attention, Today's money,
/// Beds right now and This month. Read-only; the figures come from
/// `domain/dashboard.dart`.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final c = LodgingColors.of(context);
    final now = ref.watch(boardNowProvider).value;
    final data = ref.watch(todayDataProvider);
    final rooms = ref.watch(boardRoomsProvider);
    final grace = ref.watch(boardGraceMinutesProvider).value;

    final Widget body;
    if (data.error ?? rooms.error case final error?) {
      body = Note.error('$error', title: 'Today could not be loaded.');
    } else if (now == null ||
        grace == null ||
        data.value == null ||
        rooms.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final d = data.value!;
      final beds = BedsNow.fromCounts(
        boardView(
          rooms.value!,
          const BoardFilter(),
          now: now,
          graceMinutes: grace,
        ).counts,
      );
      final money = todaysMoney(d.moves, now);
      final month = thisMonth(
        moves: d.moves,
        stays: d.stays,
        activeBeds: beds.total,
        now: now,
      );
      Widget row(Widget a, Widget b) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: Space.x20),
            Expanded(child: b),
          ],
        ),
      );
      body = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              _AttentionCard(d.awaiting, d.prices, now: now),
              _MoneyCard(money, vsLine: vsLastWeekLine(money, now)),
            ),
            const SizedBox(height: Space.x20),
            row(_BedsCard(beds), _MonthCard(month, now: now)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Today', style: t.pageTitle)),
        if (now != null)
          Text(
            formatLongDate(now),
            key: const ValueKey('today.date'),
            style: t.small.copyWith(color: c.muted),
          ),
        const SizedBox(height: Space.x20),
        Expanded(child: body),
      ],
    );
  }
}

/// A white card with a caps heading, like the phone design's.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.title,
    required this.child,
    this.badge,
    super.key,
  });

  final String title;
  final Widget? badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.cardHeading),
                ),
                if (badge != null) ...[const SizedBox(width: Space.x8), badge!],
              ],
            ),
            const SizedBox(height: Space.x12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A comparison line, "▲ 12% vs last Wednesday (KES 16,400)", in ink-soft
/// (never red or green). The arrow is drawn as an icon: the bundled fonts
/// have no ▲ ▼.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine(this.line, {required this.textKey});

  final String line;
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final style = t.small.copyWith(color: c.inkSoft);
    final (icon, rest) = switch (line) {
      _ when line.startsWith('▲ ') => (
        Icons.arrow_drop_up_rounded,
        line.substring(2),
      ),
      _ when line.startsWith('▼ ') => (
        Icons.arrow_drop_down_rounded,
        line.substring(2),
      ),
      _ => (null, line),
    };
    return Semantics(
      label: line,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 20, color: c.inkSoft),
          Flexible(
            child: Text(rest, key: textKey, style: style),
          ),
        ],
      ),
    );
  }
}

/// A thin bar of coloured segments, e.g. cash and M-Pesa.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar(this.segments, {required this.height});

  final List<(int, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final shown = [
      for (final (n, colour) in segments)
        if (n > 0) (n, colour),
    ];
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: shown.isEmpty
              ? ColoredBox(color: c.line)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (n, colour) in shown)
                      Expanded(
                        flex: n,
                        child: ColoredBox(color: colour),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Refunds to approve, then price requests (each oldest first), at most
/// [_shown] rows.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard(this.refunds, this.prices, {required this.now});

  final List<RefundAwaiting> refunds;
  final List<PriceAwaiting> prices;
  final DateTime now;

  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final rows = <Widget>[
      for (final r in refunds) _RefundRow(r),
      for (final p in prices) _PriceRow(p, now: now),
    ];
    return _TodayCard(
      key: const ValueKey('today.attention'),
      title: 'NEEDS YOUR ATTENTION',
      badge: rows.isEmpty
          ? null
          : Container(
              key: const ValueKey('today.attention.count'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x8,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: c.red,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '${rows.length}',
                style: t.smallStrong.copyWith(color: c.white),
              ),
            ),
      child: rows.isEmpty
          ? Text(
              'Nothing needs you right now.',
              key: const ValueKey('today.attention.empty'),
              style: t.body.copyWith(color: c.inkSoft),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows.take(_shown),
                if (rows.length > _shown)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x8),
                    child: Text(
                      'And ${rows.length - _shown} more.',
                      style: t.small.copyWith(color: c.muted),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow(this.refund);

  final RefundAwaiting refund;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    // Opens the owner's decision (AD-7).
    return InkWell(
      key: ValueKey('today.attention.refund.${refund.refundId}'),
      borderRadius: BorderRadius.circular(Radii.control),
      onTap: () => context.go(Routes.refundDetailFor(refund.refundId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x8),
        child: Row(
          children: [
            Container(
              width: Sizes.target - 4,
              height: Sizes.target - 4,
              decoration: BoxDecoration(
                color: c.redTint,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(Icons.replay_rounded, color: c.redText, size: 20),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Refund to approve', style: t.bodyStrong),
                  Text(
                    refund.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.x12),
            Text(formatKes(refund.amount), style: t.monoStrong),
            const SizedBox(width: Space.x8),
            Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// Figma "Attention row / Kind=Price": opens the owner's Prices, where the
/// request is decided.
class _PriceRow extends StatelessWidget {
  const _PriceRow(this.price, {required this.now});

  final PriceAwaiting price;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return InkWell(
      key: ValueKey('today.attention.price.${price.requestId}'),
      borderRadius: BorderRadius.circular(Radii.control),
      onTap: () => context.go(Routes.adminPrices),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x8),
        child: Row(
          children: [
            Container(
              width: Sizes.target - 4,
              height: Sizes.target - 4,
              decoration: BoxDecoration(
                color: c.marineTint,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(Icons.sell_outlined, color: c.marine, size: 20),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(price.title, style: t.bodyStrong),
                  Text(
                    price.subtitle(now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.x12),
            Text(price.change, style: t.monoStrong),
            const SizedBox(width: Space.x8),
            Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard(this.money, {required this.vsLine});

  final TodaysMoney money;
  final String vsLine;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final today = money.today;
    Widget method(String label, int amount, Color dot, String key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Space.x8,
          height: Space.x8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.x6),
        Text(label, style: t.body.copyWith(color: c.inkSoft)),
        const SizedBox(width: Space.x8),
        Text(formatKes(amount), key: ValueKey(key), style: t.monoStrong),
      ],
    );
    return _TodayCard(
      key: const ValueKey('today.money'),
      title: 'TODAY’S MONEY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatKes(today.net),
            key: const ValueKey('today.money.total'),
            style: t.moneyHero,
          ),
          const SizedBox(height: Space.x6),
          _ChangeLine(vsLine, textKey: const ValueKey('today.money.vs')),
          const SizedBox(height: Space.x12),
          _SegmentBar([
            (today.cash, c.marine),
            (today.mpesa, c.gold),
          ], height: Space.x8),
          const SizedBox(height: Space.x12),
          Wrap(
            spacing: Space.x24,
            runSpacing: Space.x6,
            children: [
              method('Cash', today.cash, c.marine, 'today.money.cash'),
              method('M-Pesa', today.mpesa, c.gold, 'today.money.mpesa'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BedsCard extends StatelessWidget {
  const _BedsCard(this.beds);

  final BedsNow beds;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final percent = beds.percentInUse;
    Widget chip(
      String key,
      int count,
      String label, {
      required Color fill,
      required Color ink,
      Color? border,
    }) => Container(
      key: ValueKey('today.beds.$key'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x10,
        vertical: Space.x6,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.tile),
        border: Border.all(color: border ?? fill),
      ),
      child: Row(
        children: [
          Text('$count', style: t.monoStrong.copyWith(color: ink)),
          const SizedBox(width: Space.x8),
          Text(label, style: t.body.copyWith(color: ink)),
        ],
      ),
    );
    Widget pair(Widget a, Widget b) => Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: Space.x8),
        Expanded(child: b),
      ],
    );
    return _TodayCard(
      key: const ValueKey('today.beds'),
      title: 'BEDS RIGHT NOW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${beds.inUse} of ${beds.total}',
                key: const ValueKey('today.beds.inUse'),
                style: t.moneyLarge,
              ),
              const SizedBox(width: Space.x10),
              Text(
                percent == null ? 'No beds yet' : '$percent% occupied',
                key: const ValueKey('today.beds.percent'),
                style: t.body.copyWith(color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: Space.x10),
          _SegmentBar([
            (beds.occupied, c.marine),
            (beds.overstay, c.red),
            (beds.toClean, c.butter),
            (beds.ready, c.line),
          ], height: Space.x10),
          const SizedBox(height: Space.x12),
          pair(
            chip(
              'occupied',
              beds.occupied,
              'Occupied',
              fill: c.marine,
              ink: c.white,
            ),
            chip(
              'overstay',
              beds.overstay,
              'Overstay',
              fill: c.red,
              ink: c.white,
            ),
          ),
          const SizedBox(height: Space.x8),
          pair(
            chip(
              'toClean',
              beds.toClean,
              'To clean',
              fill: c.butter,
              ink: c.butterText,
            ),
            chip(
              'ready',
              beds.ready,
              'Ready',
              fill: c.white,
              ink: c.ink,
              border: c.line,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard(this.month, {required this.now});

  final ThisMonth month;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    Widget column(String label, String value, String line, String key) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.small.copyWith(color: c.muted)),
            const SizedBox(height: Space.x4),
            Text(value, key: ValueKey('today.month.$key'), style: t.moneyLarge),
            const SizedBox(height: Space.x4),
            _ChangeLine(line, textKey: ValueKey('today.month.${key}Vs')),
          ],
        );
    final occupancy = month.occupancy;
    return _TodayCard(
      key: const ValueKey('today.month'),
      title: 'THIS MONTH · ${monthName(now)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: column(
              'Revenue so far',
              formatKes(month.revenue),
              month.revenueLine,
              'revenue',
            ),
          ),
          const SizedBox(width: Space.x16),
          Expanded(
            child: column(
              'Occupancy',
              occupancy == null ? '—' : '$occupancy%',
              month.occupancyLine,
              'occupancy',
            ),
          ),
        ],
      ),
    );
  }
}
