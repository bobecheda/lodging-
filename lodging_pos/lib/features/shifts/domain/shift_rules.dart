import '../../../core/auth/user_account.dart';
import 'shift.dart';

/// Null if valid. The float is whole KES and may be zero.
String? openingFloatError(int? amount) {
  if (amount == null) return 'Enter the opening cash float';
  if (amount < 0) return 'The float cannot be negative';
  return null;
}

/// What a signed-in user must do about shifts before working.
sealed class ShiftStart {
  const ShiftStart();
}

/// Ready to work. [shift] is the user's own open shift, or null for an admin
/// who has none (admins don't need a shift for setup work).
class ShiftReady extends ShiftStart {
  const ShiftReady(this.shift);
  final OpenShift? shift;
}

/// A receptionist with no open shift on this device must open one.
class OpenNewShift extends ShiftStart {
  const OpenNewShift();
}

/// Another receptionist's shift is still open on this device.
class ShiftBlocked extends ShiftStart {
  const ShiftBlocked(this.openShift);
  final OpenShift openShift;
}

/// [openShift] is the open shift on this device, if any (at most one).
ShiftStart shiftStartFor({
  required OpenShift? openShift,
  required String userId,
  required Role role,
}) {
  final own = openShift?.userId == userId ? openShift : null;
  if (role == Role.admin) return ShiftReady(own);
  if (openShift == null) return const OpenNewShift();
  if (own != null) return ShiftReady(own);
  // Sprint 1 has no shift close, so this blocks a second receptionist until
  // the first one's shift is closed. FD-11 (shift close) is what unblocks it.
  return ShiftBlocked(openShift);
}

/// BR-12: every check-in, renewal and payment belongs to an open shift.
class NoOpenShift implements Exception {
  const NoOpenShift();

  @override
  String toString() => 'Open a shift before taking payments';
}

/// Returns the shift a payment must use, or throws [NoOpenShift].
OpenShift requireOpenShift(OpenShift? shift) {
  if (shift == null) throw const NoOpenShift();
  return shift;
}
