/// The cards of Today (Figma "01 Today"), shared by the desk's Today and the
/// owner's phone. They show what they're given; where a row leads is the
/// screen's to say.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import '../../../core/money/kes.dart';
import '../domain/dashboard.dart';

/// A white card with a caps heading, like the phone design's.
class TodayCard extends StatelessWidget {
  const TodayCard({
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
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: t.cardHeading),
                  ),
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

/// Needs your attention: the [rows] given (oldest first in each kind), at
/// most [shown], with their count as a red badge.
class AttentionCard extends StatelessWidget {
  const AttentionCard({required this.rows, this.shown = 4, super.key});

  final List<Widget> rows;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return TodayCard(
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
                ...rows.take(shown),
                if (rows.length > shown)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x8),
                    child: Text(
                      'And ${rows.length - shown} more.',
                      style: t.small.copyWith(color: c.muted),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Which icon and colours an attention row has (Figma "Attention row").
enum AttentionKind { refund, price, shortage, voided }

/// One row of Needs your attention: an icon in its tint, a title and a
/// one-line subtitle, a figure, and a chevron when it opens something.
class AttentionRow extends StatelessWidget {
  const AttentionRow({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.figure,
    this.onTap,
    super.key,
  });

  /// A refund waiting for the owner; opens its decision (AD-7).
  factory AttentionRow.refund(RefundAwaiting refund, {VoidCallback? onTap}) =>
      AttentionRow(
        key: ValueKey('today.attention.refund.${refund.refundId}'),
        kind: AttentionKind.refund,
        title: 'Refund to approve',
        subtitle: refund.subtitle,
        figure: formatKes(refund.amount),
        onTap: onTap,
      );

  /// A price request waiting for the owner; opens Prices, where it's decided.
  factory AttentionRow.price(
    PriceAwaiting price, {
    required DateTime now,
    VoidCallback? onTap,
  }) => AttentionRow(
    key: ValueKey('today.attention.price.${price.requestId}'),
    kind: AttentionKind.price,
    title: price.title,
    subtitle: price.subtitle(now),
    figure: price.change,
    onTap: onTap,
  );

  final AttentionKind kind;
  final String title;
  final String subtitle;
  final String figure;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (icon, tint, ink) = switch (kind) {
      AttentionKind.refund => (Icons.replay_rounded, c.redTint, c.redText),
      AttentionKind.price => (Icons.sell_outlined, c.marineTint, c.marine),
      AttentionKind.shortage => (
        Icons.point_of_sale_outlined,
        c.butter,
        c.butterText,
      ),
      AttentionKind.voided => (Icons.block_rounded, c.redTint, c.redText),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x8),
        child: Row(
          children: [
            Container(
              width: Sizes.target - 4,
              height: Sizes.target - 4,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(icon, color: ink, size: 20),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.x12),
            Text(figure, style: t.monoStrong),
            if (onTap != null) ...[
              const SizedBox(width: Space.x8),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's money: net takings so far, against the same time last week,
/// with cash and M-Pesa.
class MoneyCard extends StatelessWidget {
  const MoneyCard(this.money, {required this.vsLine, super.key});

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
    return TodayCard(
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

/// Beds right now: in use of all, and the four statuses.
class BedsCard extends StatelessWidget {
  const BedsCard(this.beds, {super.key});

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
          Flexible(
            child: Text(label, style: t.body.copyWith(color: ink)),
          ),
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
    return TodayCard(
      key: const ValueKey('today.beds'),
      title: 'BEDS RIGHT NOW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wraps on a narrow phone.
          Wrap(
            spacing: Space.x10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                '${beds.inUse} of ${beds.total}',
                key: const ValueKey('today.beds.inUse'),
                style: t.moneyLarge,
              ),
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

/// This month so far: revenue and occupancy, against last month.
class MonthCard extends StatelessWidget {
  const MonthCard(this.month, {required this.now, super.key});

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
    return TodayCard(
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
