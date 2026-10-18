import '../core/auth/permissions.dart';
import '../core/auth/user_account.dart';
import '../features/shifts/domain/shift_rules.dart';

abstract final class Routes {
  static const splash = '/';
  static const oldDatabase = '/old-database';
  static const setup = '/setup';
  static const login = '/login';
  static const changePassword = '/change-password';
  static const shift = '/shift';
  static const home = '/home';
  static const guests = '/guests';

  /// FD-4; `?bed=<id>` starts with that bed chosen.
  static const checkIn = '/check-in';

  /// FD-6: find and reprint receipts.
  static const receipts = '/receipts';

  /// The shift screen, coming back to [location] once a shift is open.
  static String shiftThen(String location) =>
      Uri(path: shift, queryParameters: {'then': location}).toString();

  static String checkInFor(String? bedId) => bedId == null
      ? checkIn
      : Uri(path: checkIn, queryParameters: {'bed': bedId}).toString();
  static const adminRooms = '/admin/rooms';
  static const adminPrices = '/admin/prices';
  static const adminStaff = '/admin/users';

  /// Setup screens (AD-1) live under this prefix.
  static const setupPrefix = '/admin';

  /// The permissions each protected screen accepts, any one of them
  /// (BR-13). A screen with two parts may show the part a user can't change
  /// read-only.
  static const permissions = {
    guests: {Permission.registerGuests},
    checkIn: {Permission.checkIn},
    receipts: {Permission.printReceipts},
    adminRooms: {Permission.manageRooms},
    adminPrices: {Permission.editPrices, Permission.editSettings},
    adminStaff: {Permission.manageUsers, Permission.manageHousekeepers},
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
  static const gates = {
    splash,
    oldDatabase,
    setup,
    login,
    changePassword,
    shift,
  };
}

/// Where the app must be, given its state. Each state before "ready" allows
/// exactly one screen, so e.g. a user who must change password can reach
/// nothing else.
///
/// [hasUsers] is null while loading. [shiftStart] is null while the open
/// shift is loading (only meaningful once signed in). [schemaMatches] is
/// false when the database file was made by an older build (debug builds
/// only; null while checking), which comes before everything else.
String routeFor({
  required bool? hasUsers,
  required UserAccount? user,
  required ShiftStart? shiftStart,
  bool? schemaMatches = true,
}) {
  if (schemaMatches == null) return Routes.splash;
  if (!schemaMatches) return Routes.oldDatabase;
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
///
/// [returnTo] (the shift screen's `then`) is where to go once a gate is
/// done, instead of the bed board: e.g. back to check-in after an admin
/// opens a shift. Only a working screen [user] may open is used.
String? redirectFor(
  String location, {
  required bool? hasUsers,
  required UserAccount? user,
  required ShiftStart? shiftStart,
  bool? schemaMatches = true,
  String? returnTo,
}) {
  final target = routeFor(
    hasUsers: hasUsers,
    user: user,
    shiftStart: shiftStart,
    schemaMatches: schemaMatches,
  );
  if (target == Routes.home) {
    // AD-1: a screen needs its permission, not just a hidden menu item.
    if (!Routes.allows(location, user)) return Routes.home;
    // An admin works without a shift, so signing in never sends them to
    // the shift screen; but one with no shift of their own may go there to
    // open one (check-in takes a payment, BR-12).
    if (location == Routes.shift &&
        shiftStart is ShiftReady &&
        shiftStart.shift == null &&
        can(user!, Permission.openShift)) {
      return null;
    }
    // Once ready, any working screen is fine; only the gates send you on.
    if (!Routes.gates.contains(location)) return null;
    return _workingScreen(returnTo, user) ?? Routes.home;
  }
  return target == location ? null : target;
}

/// [location] if it's a working screen (not a gate) that [user] may open.
String? _workingScreen(String? location, UserAccount? user) {
  final uri = location == null ? null : Uri.tryParse(location);
  if (uri == null || !location!.startsWith('/') || uri.hasAuthority) {
    return null;
  }
  if (Routes.gates.contains(uri.path) || !Routes.allows(uri.path, user)) {
    return null;
  }
  return location;
}
