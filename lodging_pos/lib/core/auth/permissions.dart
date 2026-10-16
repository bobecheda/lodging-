import 'user_account.dart';

/// Every protected action (BR-13). Access is always checked through
/// [permissionMap], never by comparing roles, so a new role (e.g. a
/// supervisor) only needs an edit to the map. Each story wires its own check.
enum Permission {
  // Setup and oversight.
  manageRooms,
  editPrices,
  editSettings,
  manageUsers,
  manageHousekeepers,
  voidRecords,
  approveRefund,
  viewAllReports,
  viewAuditTrail,
  manageInventoryItems,
  recordExpenses,

  /// Setup work without opening a shift. Money still needs an open shift.
  workWithoutShift,

  // Front desk.
  openShift,
  closeShift,
  checkIn,
  extendStay,
  checkOut,
  requestRefund,
  payRefund,
  assignHousekeeping,
  markClean,
  recordStock,
  viewOwnReport,
}

const _adminOnly = {Role.admin};
const _everyone = {Role.admin, Role.receptionist};

/// Who may do what. The only place roles are named for access.
const permissionMap = <Permission, Set<Role>>{
  Permission.manageRooms: _adminOnly,
  Permission.editPrices: _adminOnly,
  Permission.editSettings: _adminOnly,
  Permission.manageUsers: _adminOnly,
  Permission.manageHousekeepers: _adminOnly,
  Permission.voidRecords: _adminOnly,
  Permission.approveRefund: _adminOnly,
  Permission.viewAllReports: _adminOnly,
  Permission.viewAuditTrail: _adminOnly,
  Permission.manageInventoryItems: _adminOnly,
  Permission.recordExpenses: _adminOnly,
  Permission.workWithoutShift: _adminOnly,
  Permission.openShift: _everyone,
  Permission.closeShift: _everyone,
  Permission.checkIn: _everyone,
  Permission.extendStay: _everyone,
  Permission.checkOut: _everyone,
  Permission.requestRefund: _everyone,
  Permission.payRefund: _everyone,
  Permission.assignHousekeeping: _everyone,
  Permission.markClean: _everyone,
  Permission.recordStock: _everyone,
  Permission.viewOwnReport: _everyone,
};

/// Whether [user] may do [permission]. A disabled user may do nothing.
bool can(UserAccount user, Permission permission) =>
    user.isActive && (permissionMap[permission]?.contains(user.role) ?? false);

/// [user] tried an action their role doesn't allow. Screens hide what a user
/// can't do; this is the check that can't be bypassed by reaching a
/// repository directly.
class NotPermitted implements Exception {
  const NotPermitted(this.permission);
  final Permission permission;

  @override
  String toString() => 'You are not allowed to do this.';
}

/// Throws [NotPermitted] unless [user] may do [permission].
void requirePermission(UserAccount user, Permission permission) {
  if (!can(user, permission)) throw NotPermitted(permission);
}
