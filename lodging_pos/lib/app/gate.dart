import '../core/auth/permissions.dart';
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
  static const adminPrices = '/admin/prices';

  /// Setup screens (AD-1) live under this prefix.
  static const setupPrefix = '/admin';

  /// The permissions each protected screen accepts, any one of them
  /// (BR-13). A screen with two parts may show the part a user can't change
  /// read-only.
  static const permissions = {
    adminRooms: {Permission.manageRooms},
    adminPrices: {Permission.editPrices, Permission.editSettings},
  };

  /// Whether [user] may open [location]. A setup route missing from
  /// [permissions] is closed to everyone, so a new screen fails safe.
  static bool allows(String location, UserAccount? user) {
    final needed = permissions[location];
    if (needed != null) return user != null && needed.any((p) => can(user, p));
    final isSetup =
        location == setupPrefix || location.startsWith('$setupPrefix/');
    return !isSetup;
  }

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
    // AD-1: a screen needs its permission, not just a hidden menu item.
    if (!Routes.allows(location, user)) return Routes.home;
    // Once ready, any working screen is fine; only the gates send you home.
    if (!Routes.gates.contains(location)) return null;
  }
  return target == location ? null : target;
}
