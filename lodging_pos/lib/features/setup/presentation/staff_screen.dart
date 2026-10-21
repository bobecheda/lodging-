import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import 'widgets/housekeepers_card.dart';
import 'widgets/users_card.dart';

/// AD-4 "Users and staff": people who sign in beside the housekeepers list
/// (artboard "Setup — users and housekeepers"). The owner's "Staff" is the
/// supervisors only, without housekeepers.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final housekeepers =
        user != null && can(user, Permission.manageHousekeepers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            housekeepers ? 'Users and staff' : 'Staff',
            style: t.pageTitle,
          ),
        ),
        const SizedBox(height: Space.x20),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 3, child: UsersCard()),
                const SizedBox(width: Space.x24),
                Expanded(
                  flex: 2,
                  child: housekeepers
                      ? const HousekeepersCard()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
