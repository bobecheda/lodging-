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

  /// Find, register and correct guests (FD-3). Exporting guest data will be
  /// a separate permission.
  registerGuests,

  /// Find receipts and print or save them; after the first, they print as
  /// COPY (FD-6).
  printReceipts,

  /// Close someone else's shift with a cash count (FD-11), e.g. one left
  /// open by a receptionist who went home. Supervisor only for now; a
  /// receptionist "handover close" later only needs this map changed.
  closeOtherShifts,

  /// "Back up now" and the backup folders on the Backups card. The daily
  /// backups themselves run for everyone, signed in or not.
  manageBackups,

  // The owner's business view (sprint 2). Mapped now; their screens and
  // flows are separate stories.

  /// Ask the owner to change a category's price (BR-2).
  requestPriceChange,

  /// Approve or reject a requested price change (BR-2).
  decidePriceChange,

  /// The owner's dashboard: takings, beds, alerts, profit.
  viewBusinessDashboard,

  /// Create, reset and disable supervisors.
  manageSupervisors,
}

const _ownerOnly = {Role.owner};
const _supervisorOnly = {Role.supervisor};
const _ownerAndSupervisor = {Role.owner, Role.supervisor};

/// The front desk: supervisors and receptionists. The owner works from the
/// business view, not the desk.
const _desk = {Role.supervisor, Role.receptionist};

/// Who may do what. The only place roles are named for access.
const permissionMap = <Permission, Set<Role>>{
  // The owner: money decisions and the business view.
  Permission.approveRefund: _ownerOnly,
  Permission.decidePriceChange: _ownerOnly,
  Permission.viewBusinessDashboard: _ownerOnly,
  Permission.manageSupervisors: _ownerOnly,
  Permission.viewAllReports: _ownerAndSupervisor,
  Permission.viewAuditTrail: _ownerAndSupervisor,
  // TEMPORARY: moves to owner + requestPriceChange in the sprint 2 owner
  // sign-in story (prd.md, BR-2). Until the owner can sign in, the
  // supervisor sets prices and adds or closes categories.
  Permission.editPrices: _supervisorOnly,
  // The supervisor: setup, staff, settings, shift oversight.
  Permission.requestPriceChange: _supervisorOnly,
  Permission.manageRooms: _supervisorOnly,
  Permission.editSettings: _supervisorOnly,
  Permission.manageUsers: _supervisorOnly,
  Permission.manageHousekeepers: _supervisorOnly,
  Permission.voidRecords: _supervisorOnly,
  Permission.manageInventoryItems: _supervisorOnly,
  Permission.recordExpenses: _supervisorOnly,
  Permission.workWithoutShift: _supervisorOnly,
  Permission.closeOtherShifts: _supervisorOnly,
  Permission.manageBackups: _supervisorOnly,
  // The front desk.
  Permission.openShift: _desk,
  Permission.closeShift: _desk,
  Permission.checkIn: _desk,
  Permission.extendStay: _desk,
  Permission.checkOut: _desk,
  Permission.requestRefund: _desk,
  Permission.payRefund: _desk,
  Permission.assignHousekeeping: _desk,
  Permission.markClean: _desk,
  Permission.recordStock: _desk,
  Permission.viewOwnReport: _desk,
  Permission.registerGuests: _desk,
  Permission.printReceipts: _desk,
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
