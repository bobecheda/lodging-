import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../dashboard/presentation/today_cards.dart';
import '../data/owner_cloud.dart';
import '../domain/owner_today.dart';
import 'owner_providers.dart';

/// The owner's Money (Figma "04 Money"): today, this week or this month so
/// far, net (payments − refunds paid − anything voided) against the same
/// point before; the last 14 days; cash against M-Pesa; and the nights let
/// by category. Every figure comes from `dashboard/domain`, the desk's own
/// code, and every chart also says its amounts in text.
class OwnerMoneyScreen extends ConsumerStatefulWidget {
  const OwnerMoneyScreen({super.key});

  @override
  ConsumerState<OwnerMoneyScreen> createState() => _OwnerMoneyState();
}

class _OwnerMoneyState extends ConsumerState<OwnerMoneyScreen> {
  var _period = MoneyPeriod.month;
  var _eachDay = false;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final now = ref.watch(ownerClockProvider).now();
    final data = ref.watch(ownerTodayDataProvider);
    final today = data.value?.today;
    if (today == null) {
      return data.hasError
          ? Padding(
              padding: const EdgeInsets.all(Space.x16),
              child: Note.error(
                data.error is OwnerCloudOffline
                    ? 'No internet connection. Money shows once the phone is '
                          'online.'
                    : '${data.error}',
                title: 'Money could not be loaded.',
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    final money = periodMoney(today.moves, _period, now);
    final days = dailyNet(today.moves, now);
    final dates = periodDates(_period, now);
    final categories = nightsLetByCategory(
      today.stays,
      first: dates.first,
      last: dates.last,
    );
    return RefreshIndicator(
      onRefresh: () => ref.read(ownerTodayDataProvider.notifier).refresh(),
      child: ListView(
        key: const ValueKey('owner.money'),
        padding: const EdgeInsets.all(Space.x16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Semantics(header: true, child: Text('Money', style: t.pageTitle)),
          const SizedBox(height: Space.x4),
          Text(
            freshnessLine(today.desks, now),
            key: const ValueKey('owner.money.fresh'),
            style: t.small.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.x12),
          _PeriodTabs(
            selected: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: Space.x12),
          _TotalCard(money),
          const SizedBox(height: Space.x12),
          _DailyCard(
            days,
            showEach: _eachDay,
            onToggle: () => setState(() => _eachDay = !_eachDay),
          ),
          const SizedBox(height: Space.x12),
          _SplitCard(money),
          const SizedBox(height: Space.x12),
          _CategoryCard(categories),
        ],
      ),
    );
  }
}

/// Today · This week · This month (a grey track, the chosen one white).
class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onChanged});

  final MoneyPeriod selected;
  final ValueChanged<MoneyPeriod> onChanged;

  static const _labels = {
    MoneyPeriod.today: 'Today',
    MoneyPeriod.week: 'This week',
    MoneyPeriod.month: 'This month',
  };

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.lineSoft,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          for (final p in MoneyPeriod.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: p == selected,
                inMutuallyExclusiveGroup: true,
                child: InkWell(
                  key: ValueKey('owner.money.period.${p.name}'),
                  borderRadius: BorderRadius.circular(Radii.control),
                  onTap: () => onChanged(p),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: Sizes.targetCompact,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x4,
                      vertical: Space.x6,
                    ),
                    decoration: p == selected
                        ? BoxDecoration(
                            color: c.white,
                            borderRadius: BorderRadius.circular(Radii.control),
                            border: Border.all(color: c.line),
                          )
                        : null,
                    child: Text(
                      _labels[p]!,
                      textAlign: TextAlign.center,
                      style: p == selected ? t.bodyStrong : t.body,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A label on the left, an amount on the right.
class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.amount, {required this.amountKey});

  final String label;
  final String amount;
  final Key amountKey;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: t.body.copyWith(color: c.inkSoft)),
          ),
          const SizedBox(width: Space.x12),
          Text(amount, key: amountKey, style: t.monoStrong),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard(this.money);

  final PeriodMoney money;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return TodayCard(
      key: const ValueKey('owner.money.total'),
      title: money.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatKes(money.net),
            key: const ValueKey('owner.money.net'),
            style: t.moneyHero,
          ),
          const SizedBox(height: Space.x8),
          _AmountRow(
            'Received',
            formatKes(money.received),
            amountKey: const ValueKey('owner.money.received'),
          ),
          _AmountRow(
            'Refunds paid',
            '− ${formatKes(money.refundsPaid)}',
            amountKey: const ValueKey('owner.money.refunds'),
          ),
          _AmountRow(
            money.beforeLabel,
            formatKes(money.before),
            amountKey: const ValueKey('owner.money.before'),
          ),
          if (money.voided > 0) ...[
            const SizedBox(height: Space.x4),
            Text(
              '${formatKes(money.voided)} voided, not counted.',
              key: const ValueKey('owner.money.voided'),
              style: t.small.copyWith(color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "DAILY NET · LAST 14 DAYS": a bar a day (today in gold), what they say
/// in a line, and every day as text on "Show each day".
class _DailyCard extends StatelessWidget {
  const _DailyCard(this.days, {required this.showEach, required this.onToggle});

  final List<DayNet> days;
  final bool showEach;
  final VoidCallback onToggle;

  static const _height = 140.0;

  String _short(DateTime day) {
    final full = formatDayDate(
      nairobiInstant(day.year, day.month, day.day, 12),
    );
    return full.substring(0, full.lastIndexOf(' ')); // "Thu 8"
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final most = days.fold(0, (m, d) => d.net > m ? d.net : m);
    return TodayCard(
      key: const ValueKey('owner.money.daily'),
      title: 'DAILY NET · LAST ${days.length} DAYS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in days.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.x4),
                  Expanded(
                    child: Semantics(
                      key: ValueKey('owner.money.bar.$i'),
                      // Each bar is read on its own, day and amount.
                      container: true,
                      label: i == days.length - 1
                          ? 'Today so far · ${formatKes(d.net)}'
                          : dayLine(d),
                      excludeSemantics: true,
                      child: Container(
                        height: most <= 0 || d.net <= 0
                            ? Space.x4
                            : (d.net / most * _height).clamp(Space.x4, _height),
                        decoration: BoxDecoration(
                          color: d.net <= 0
                              ? c.line
                              : i == days.length - 1
                              ? c.gold
                              : c.marine,
                          borderRadius: BorderRadius.circular(Radii.badge),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.x8),
          ExcludeSemantics(
            child: Row(
              children: [
                Text(
                  _short(days.first.day),
                  style: t.small.copyWith(color: c.muted),
                ),
                const Spacer(),
                Text(
                  _short(days[days.length ~/ 2].day),
                  style: t.small.copyWith(color: c.muted),
                ),
                const Spacer(),
                Text('Today', style: t.small.copyWith(color: c.muted)),
              ],
            ),
          ),
          const SizedBox(height: Space.x8),
          Text(
            dailySummary(days),
            key: const ValueKey('owner.money.dailySummary'),
            style: t.small.copyWith(color: c.inkSoft),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('owner.money.eachDay'),
              onPressed: onToggle,
              child: Text(showEach ? 'Hide each day' : 'Show each day'),
            ),
          ),
          if (showEach)
            for (final (i, d) in days.reversed.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x4),
                child: Text(
                  i == 0 ? 'Today so far · ${formatKes(d.net)}' : dayLine(d),
                  key: ValueKey('owner.money.day.${days.length - 1 - i}'),
                  style: t.mono,
                ),
              ),
        ],
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard(this.money);

  final PeriodMoney money;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final takings = money.takings;
    String share(String name, int? percent) =>
        percent == null ? name : '$name · $percent%';
    return TodayCard(
      key: const ValueKey('owner.money.split'),
      title: money.splitTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Space.x10 / 2),
              child: SizedBox(
                height: Space.x10,
                child: takings.cash <= 0 && takings.mpesa <= 0
                    ? ColoredBox(color: c.line)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (takings.cash > 0)
                            Expanded(
                              flex: takings.cash,
                              child: ColoredBox(color: c.marine),
                            ),
                          if (takings.mpesa > 0)
                            Expanded(
                              flex: takings.mpesa,
                              child: ColoredBox(color: c.gold),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: Space.x8),
          _AmountRow(
            share('Cash', money.cashPercent),
            formatKes(takings.cash),
            amountKey: const ValueKey('owner.money.cash'),
          ),
          _AmountRow(
            share('M-Pesa', money.mpesaPercent),
            formatKes(takings.mpesa),
            amountKey: const ValueKey('owner.money.mpesa'),
          ),
        ],
      ),
    );
  }
}

/// "BY CATEGORY · NIGHTS LET": nights stayed in the period, by category,
/// at each stay's locked price.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard(this.rows);

  final List<CategoryNights> rows;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final most = rows.fold(0, (m, r) => r.value > m ? r.value : m);
    return TodayCard(
      key: const ValueKey('owner.money.categories'),
      title: 'BY CATEGORY · NIGHTS LET',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Text(
              'No nights let in this period yet.',
              style: t.body.copyWith(color: c.inkSoft),
            ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: Space.x8,
                          children: [
                            Text(r.name, style: t.bodyStrong),
                            Text(
                              r.line,
                              key: ValueKey('owner.money.nights.${r.name}'),
                              style: t.small.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.x12),
                      Text(
                        formatKes(r.value),
                        key: ValueKey('owner.money.value.${r.name}'),
                        style: t.monoStrong,
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.x6),
                  ExcludeSemantics(
                    child: FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: most == 0 ? 0 : r.value / most,
                      child: Container(
                        height: Space.x6,
                        decoration: BoxDecoration(
                          color: c.marine,
                          borderRadius: BorderRadius.circular(Space.x6 / 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.x8),
          Text(
            'Value of nights stayed in this period. Net above counts money on '
            'the day it was paid, so the two won’t match.',
            key: const ValueKey('owner.money.categoriesNote'),
            style: t.small.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
