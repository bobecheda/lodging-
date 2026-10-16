import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import 'widgets/housekeepers_card.dart';
import 'widgets/users_card.dart';

/// AD-4 "Users and staff": people who sign in beside the housekeepers list
/// (artboard "Setup — users and housekeepers").
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Users and staff', style: t.pageTitle),
        ),
        const SizedBox(height: Space.x20),
        const Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: UsersCard()),
                SizedBox(width: Space.x24),
                Expanded(flex: 2, child: HousekeepersCard()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
