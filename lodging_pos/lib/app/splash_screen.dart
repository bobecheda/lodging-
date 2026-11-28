import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/schema_check.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/shifts/presentation/shift_providers.dart';
import 'startup/startup_providers.dart';
import 'theme/theme.dart';
import 'widgets/notes.dart';

/// Shown while the database opens and the app works out where to go.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error =
        ref.watch(schemaDriftProvider).error ??
        ref.watch(startupTasksProvider).error ??
        ref.watch(setupStatusProvider).error ??
        ref.watch(currentShiftProvider).error;
    // story/desk-db-guards-2: the cloud is asked before sign-in.
    final checking =
        ref.watch(startupTasksProvider).hasValue &&
        ref.watch(cloudStartupCheckProvider).isLoading;
    return Scaffold(
      body: Center(
        child: error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (checking) ...[
                    const SizedBox(height: Space.x16),
                    Text(
                      'Checking with the cloud…',
                      key: const ValueKey('splash.cloudCheck'),
                      style: LodgingType.of(context).secondary,
                    ),
                  ],
                ],
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Sizes.formMaxWidth),
                child: Note.error(
                  '$error',
                  title: 'The local database could not be opened.',
                ),
              ),
      ),
    );
  }
}
