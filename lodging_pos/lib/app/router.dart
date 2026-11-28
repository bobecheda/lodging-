import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth/session.dart';
import '../core/database/schema_check.dart';
import '../core/sync/sync_providers.dart';
import '../features/auth/domain/setup.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/setup_screen.dart';
import '../features/bed_board/presentation/bed_board_screen.dart';
import '../features/dashboard/presentation/today_screen.dart';
import '../features/guests/presentation/guests_screen.dart';
import '../features/receipts/presentation/receipts_screen.dart';
import '../features/shifts/domain/drawer.dart';
import '../features/shifts/presentation/cash_screen.dart';
import '../features/shifts/presentation/drawer_count_screen.dart';
import '../features/voids/presentation/voids_screen.dart';
import '../features/refunds/presentation/refund_detail_screen.dart';
import '../features/refunds/presentation/refunds_screen.dart';
import '../features/stays/presentation/check_in_screen.dart';
import '../features/shifts/domain/shift_rules.dart';
import '../features/shifts/presentation/close_shift_screen.dart';
import '../features/shifts/presentation/open_shift_screen.dart';
import '../features/shifts/presentation/shifts_screen.dart';
import '../features/shifts/presentation/shift_providers.dart';
import 'gate.dart';
import '../features/setup/presentation/prices_screen.dart';
import '../features/setup/presentation/rooms_screen.dart';
import '../features/setup/presentation/staff_screen.dart';
import 'old_database_screen.dart';
import 'page_transitions.dart';
import 'shell/desk_shell.dart';
import 'splash_screen.dart';
import 'startup/startup_providers.dart';
import 'startup/behind_cloud_screen.dart';
import 'startup/unusual_start_screen.dart';

part 'router.g.dart';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Re-run the redirect whenever the gate's inputs change.
  final refresh = ValueNotifier(0);
  void bump() => refresh.value++;
  ref
    ..listen(schemaDriftProvider, (_, _) => bump())
    ..listen(startupTasksProvider, (_, _) => bump())
    ..listen(cloudStartupCheckProvider, (_, _) => bump())
    ..listen(deskBehindProvider, (_, _) => bump())
    ..listen(unusualStartProvider, (_, _) => bump())
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
      // A failed check falls through, so its error shows on the splash. The
      // startup tasks (an accepted restore, the build stamp) finish first,
      // then the cloud is asked whether this file is behind it.
      schemaMatches: switch ((
        ref.read(schemaDriftProvider),
        ref.read(startupTasksProvider),
        ref.read(cloudStartupCheckProvider),
      )) {
        (AsyncData(:final value), _, _) when value != null => false,
        (AsyncError(), _, _) || (_, AsyncError(), _) => true,
        (AsyncData(), AsyncData(), AsyncData() || AsyncError()) => true,
        _ => null,
      },
      unusualStart: ref.read(unusualStartProvider) != null,
      behindCloud: ref.read(deskBehindProvider) != null,
      hasUsers: switch (ref.read(setupStatusProvider).value) {
        null => null,
        final setup => setup != SetupState.fresh,
      },
      hasOwner: switch (ref.read(setupStatusProvider).value) {
        null => null,
        final setup => setup != SetupState.needsOwner,
      },
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
      GoRoute(
        path: Routes.unusualStart,
        builder: (_, _) => const UnusualStartScreen(),
      ),
      GoRoute(
        path: Routes.behindCloud,
        builder: (_, _) => const BehindCloudScreen(),
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
      // Close shift is a focused flow: no navigation (v2 PR 3).
      GoRoute(
        path: Routes.closeShift,
        builder: (_, state) => FocusedFlow(
          child: CloseShiftScreen(
            key: ValueKey(state.uri.toString()),
            shiftId: state.uri.queryParameters['shift'],
          ),
        ),
      ),
      // Working screens live inside the desk shell (top bar + content).
      ShellRoute(
        builder: (context, state, child) =>
            DeskShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (_, state) => deskPage(
              state,
              BedBoardScreen(openStayId: state.uri.queryParameters['stay']),
            ),
          ),
          GoRoute(
            path: Routes.today,
            pageBuilder: (_, state) => deskPage(state, const TodayScreen()),
          ),
          GoRoute(
            path: Routes.refundDetail,
            pageBuilder: (_, state) => deskPage(
              state,
              RefundDetailScreen(
                key: ValueKey(state.uri.toString()),
                refundId: state.uri.queryParameters['id'] ?? '',
              ),
              kind: PageKind.flow,
            ),
          ),
          GoRoute(
            path: Routes.refunds,
            pageBuilder: (_, state) => deskPage(
              state,
              RefundsScreen(openRefundId: state.uri.queryParameters['pay']),
            ),
          ),
          GoRoute(
            path: Routes.guests,
            pageBuilder: (_, state) => deskPage(state, const GuestsScreen()),
          ),
          GoRoute(
            path: Routes.checkIn,
            // A new state per address, so each bed starts fresh.
            pageBuilder: (_, state) => deskPage(
              state,
              CheckInScreen(
                key: ValueKey(state.uri.toString()),
                bedId: state.uri.queryParameters['bed'],
              ),
              kind: PageKind.flow,
            ),
          ),
          GoRoute(
            path: Routes.receipts,
            pageBuilder: (_, state) => deskPage(
              state,
              ReceiptsScreen(
                key: ValueKey(state.uri.toString()),
                query: state.uri.queryParameters['q'],
                receiptId: state.uri.queryParameters['receipt'],
              ),
            ),
          ),
          GoRoute(
            path: Routes.voids,
            pageBuilder: (_, state) => deskPage(state, const VoidsScreen()),
          ),
          GoRoute(
            path: Routes.cash,
            pageBuilder: (_, state) => deskPage(state, const CashScreen()),
          ),
          GoRoute(
            path: Routes.drawerCount,
            pageBuilder: (_, state) => deskPage(
              state,
              DrawerCountScreen(
                key: ValueKey(state.uri.toString()),
                kind: state.uri.queryParameters['kind'] == 'collect'
                    ? DrawerCountKind.collect
                    : DrawerCountKind.check,
              ),
              kind: PageKind.flow,
            ),
          ),
          GoRoute(
            path: Routes.shifts,
            pageBuilder: (_, state) => deskPage(state, const ShiftsScreen()),
          ),
          GoRoute(
            path: Routes.adminRooms,
            pageBuilder: (_, state) => deskPage(state, const RoomsScreen()),
          ),
          GoRoute(
            path: Routes.adminPrices,
            pageBuilder: (_, state) => deskPage(state, const PricesScreen()),
          ),
          GoRoute(
            path: Routes.adminStaff,
            pageBuilder: (_, state) => deskPage(state, const StaffScreen()),
          ),
        ],
      ),
    ],
  );
}
