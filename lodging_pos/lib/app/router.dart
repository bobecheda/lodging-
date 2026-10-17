import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth/session.dart';
import '../core/database/schema_check.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/setup_screen.dart';
import '../features/bed_board/presentation/bed_board_screen.dart';
import '../features/guests/presentation/guests_screen.dart';
import '../features/stays/presentation/check_in_screen.dart';
import '../features/shifts/domain/shift_rules.dart';
import '../features/shifts/presentation/open_shift_screen.dart';
import '../features/shifts/presentation/shift_providers.dart';
import 'gate.dart';
import '../features/setup/presentation/prices_screen.dart';
import '../features/setup/presentation/rooms_screen.dart';
import '../features/setup/presentation/staff_screen.dart';
import 'old_database_screen.dart';
import 'shell/desk_shell.dart';
import 'splash_screen.dart';

part 'router.g.dart';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Re-run the redirect whenever the gate's inputs change.
  final refresh = ValueNotifier(0);
  void bump() => refresh.value++;
  ref
    ..listen(schemaDriftProvider, (_, _) => bump())
    ..listen(setupStatusProvider, (_, _) => bump())
    ..listen(sessionProvider, (_, _) => bump())
    ..listen(currentShiftProvider, (_, _) => bump())
    ..listen(shiftContinuedProvider, (_, _) => bump())
    ..onDispose(refresh.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final user = ref.read(sessionProvider);
    final shift = ref.read(currentShiftProvider);
    return redirectFor(
      state.matchedLocation,
      returnTo: state.uri.queryParameters['then'],
      // A failed check falls through, so its error shows on the splash.
      schemaMatches: switch (ref.read(schemaDriftProvider)) {
        AsyncData(:final value) => value == null,
        AsyncError() => true,
        _ => null,
      },
      hasUsers: ref.read(setupStatusProvider).value,
      user: user,
      shiftStart: user == null || !shift.hasValue
          ? null
          : shiftStartFor(
              openShift: shift.value,
              user: user,
              resumeConfirmed: ref.read(shiftContinuedProvider),
            ),
    );
  }

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.oldDatabase,
        builder: (_, _) => const OldDatabaseScreen(),
      ),
      GoRoute(path: Routes.setup, builder: (_, _) => const SetupScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.shift,
        builder: (_, state) =>
            OpenShiftScreen(returnTo: state.uri.queryParameters['then']),
      ),
      // Working screens live inside the desk shell (sidebar + content).
      ShellRoute(
        builder: (context, state, child) =>
            DeskShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const BedBoardScreen()),
          GoRoute(path: Routes.guests, builder: (_, _) => const GuestsScreen()),
          GoRoute(
            path: Routes.checkIn,
            // A new state per address, so each bed starts fresh.
            builder: (_, state) => CheckInScreen(
              key: ValueKey(state.uri.toString()),
              bedId: state.uri.queryParameters['bed'],
            ),
          ),
          GoRoute(
            path: Routes.adminRooms,
            builder: (_, _) => const RoomsScreen(),
          ),
          GoRoute(
            path: Routes.adminPrices,
            builder: (_, _) => const PricesScreen(),
          ),
          GoRoute(
            path: Routes.adminStaff,
            builder: (_, _) => const StaffScreen(),
          ),
        ],
      ),
    ],
  );
}
