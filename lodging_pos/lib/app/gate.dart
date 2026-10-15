import '../core/auth/user_account.dart';
import '../features/shifts/domain/shift_rules.dart';

abstract final class Routes {
  static const splash = '/';
  static const setup = '/setup';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const shift = '/shift';
  static const home = '/home';
  static const adminRooms = '/admin/rooms';

  /// Owner-only screens (AD-1) live under this prefix.
  static const ownerOnlyPrefix = '/admin';

  static bool isOwnerOnly(String location) =>
      location == ownerOnlyPrefix || location.startsWith('$ownerOnlyPrefix/');

  /// Screens that only exist to get the user ready to work.
  static const gates = {splash, setup, login, changePassword, shift};
}

/// Where the app must be, given its state. Each state before "ready" allows
/// exactly one screen, so e.g. a user who must change password can reach
/// nothing else.
///
/// [hasUsers] is null while loading. [shiftStart] is null while the open
/// shift is loading (only meaningful once signed in).
String routeFor({
  required bool? hasUsers,
  required UserAccount? user,
  required ShiftStart? shiftStart,
}) {
  if (hasUsers == null) return Routes.splash;
  if (!hasUsers) return Routes.setup;
  if (user == null) return Routes.login;
  if (user.mustChangePassword) return Routes.changePassword;
  return switch (shiftStart) {
    null => Routes.splash,
    ShiftReady() => Routes.home,
    ResumeShift() || OpenNewShift() || ShiftBlocked() => Routes.shift,
  };
}

/// GoRouter redirect: null to stay on [location].
String? redirectFor(
  String location, {
  required bool? hasUsers,
  required UserAccount? user,
  required ShiftStart? shiftStart,
}) {
  final target = routeFor(
    hasUsers: hasUsers,
    user: user,
    shiftStart: shiftStart,
  );
  if (target == Routes.home) {
    // AD-1: receptionists never reach owner-only screens.
    if (Routes.isOwnerOnly(location) && user?.role != Role.admin) {
      return Routes.home;
    }
    // Once ready, any working screen is fine; only the gates send you home.
    if (!Routes.gates.contains(location)) return null;
  }
  return target == location ? null : target;
}
