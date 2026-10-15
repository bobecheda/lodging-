import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/clock/clock.dart';
import '../core/clock/nairobi.dart';
import '../core/money/kes.dart';
import '../features/shifts/presentation/shift_providers.dart';
import 'theme/theme.dart';
import 'widgets/notes.dart';

/// Placeholder for the bed board until FD-2.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final shift = ref.watch(currentShiftProvider).value;
    final own = shift?.userId == user?.id ? shift : null;
    final now = ref.watch(clockProvider).now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Bed board', style: t.pageTitle)),
        const SizedBox(height: Space.x4),
        Text(formatDayDateTime(now), style: t.small),
        const SizedBox(height: Space.x24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.x20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR SHIFT', style: t.cardHeading),
                const SizedBox(height: Space.x8),
                Text(
                  own == null
                      ? 'No shift open. Payments need an open shift.'
                      : 'Shift open since ${formatTime(own.openedAt)} · '
                            'float ${formatKes(own.openingFloat)}',
                  key: const ValueKey('home.shift'),
                  style: t.body,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x16),
        const Note.info('The bed board arrives with story FD-2.'),
      ],
    );
  }
}
