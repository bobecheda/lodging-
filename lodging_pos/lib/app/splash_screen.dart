import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/auth_providers.dart';
import '../features/shifts/presentation/shift_providers.dart';

/// Shown while the database opens and the app works out where to go.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error =
        ref.watch(setupStatusProvider).error ??
        ref.watch(currentShiftProvider).error;
    return Scaffold(
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'The local database could not be opened.\n$error',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}
