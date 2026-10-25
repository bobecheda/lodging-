import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/brand_wordmark.dart';
import '../../dashboard/domain/dashboard.dart';
import '../domain/owner_today.dart';
import 'owner_app.dart';
import 'owner_providers.dart';

/// The phone's frame (Figma "01 Today"): the marine header (wordmark,
/// date, when the figures were loaded, the desk's state), the screen, and
/// the bottom bar. Coming back to the app reloads Today.
class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  late final AppLifecycleListener _lifecycle;

  /// Moves "Updated N min ago" on between reloads (off in tests).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          unawaited(ref.read(ownerTodayDataProvider.notifier).refresh()),
    );
    if (ref.read(ownerRefreshIntervalProvider) != null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.location == OwnerRoutes.refund
        ? OwnerRoutes.today
        : widget.location.startsWith('${OwnerRoutes.more}/')
        ? OwnerRoutes.more
        : widget.location;
    final index = OwnerRoutes.tabs.indexOf(at);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(now: ref.watch(ownerClockProvider).now()),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('owner.nav'),
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(OwnerRoutes.tabs[i]),
        destinations: const [
          NavigationDestination(
            key: ValueKey('owner.nav.today'),
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            key: ValueKey('owner.nav.money'),
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments_rounded),
            label: 'Money',
          ),
          NavigationDestination(
            key: ValueKey('owner.nav.beds'),
            icon: Icon(Icons.bed_outlined),
            selectedIcon: Icon(Icons.bed_rounded),
            label: 'Beds',
          ),
          NavigationDestination(
            key: ValueKey('owner.nav.prices'),
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell_rounded),
            label: 'Prices',
          ),
          NavigationDestination(
            key: ValueKey('owner.nav.more'),
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final snapshot = ref.watch(ownerTodayDataProvider).value;
    final onMarine = t.small.copyWith(color: c.brandCream);
    final desk = snapshot == null ? null : deskLine(snapshot.today.desks, now);
    return ColoredBox(
      color: c.marine,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x16,
            Space.x12,
            Space.x16,
            Space.x12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BrandWordmark(
                      name: snapshot?.today.lodgingName ?? '',
                      size: WordmarkSize.bar,
                    ),
                  ),
                  const SizedBox(width: Space.x12),
                  Text(
                    formatLongDate(now),
                    key: const ValueKey('owner.date'),
                    style: onMarine,
                  ),
                ],
              ),
              if (snapshot != null) ...[
                const SizedBox(height: Space.x8),
                Text(
                  updatedLine(
                    snapshot.loadedAt,
                    now,
                    offline: snapshot.offline,
                  ),
                  key: const ValueKey('owner.updated'),
                  style: t.smallStrong.copyWith(
                    color: snapshot.offline ? c.butter : c.white,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: Space.x8,
                      color: desk!.online ? c.syncOnline : c.navMuted,
                    ),
                    const SizedBox(width: Space.x6),
                    Expanded(
                      child: Text(
                        desk.text,
                        key: const ValueKey('owner.desk'),
                        style: onMarine,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
