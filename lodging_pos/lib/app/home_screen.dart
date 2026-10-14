import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/auth/user_account.dart';
import '../core/clock/nairobi.dart';
import '../core/money/kes.dart';
import '../features/shifts/presentation/shift_providers.dart';

/// Placeholder until the bed board (FD-2) becomes the home screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final shift = ref.watch(currentShiftProvider).value;
    final own = shift?.userId == user?.id ? shift : null;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lodging POS'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user != null)
              Text(
                'Signed in as ${user.fullName} '
                '(${user.role == Role.admin ? 'Admin' : 'Receptionist'})',
                style: text.titleMedium,
              ),
            const SizedBox(height: 8),
            Text(
              own == null
                  ? 'No shift open. Payments need an open shift.'
                  : 'Shift open since ${formatNairobi(own.openedAt)} · '
                        'float ${formatKes(own.openingFloat)}',
              key: const ValueKey('home.shift'),
            ),
          ],
        ),
      ),
    );
  }
}
