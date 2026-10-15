import 'user_account.dart';

/// An owner-only action was attempted by a receptionist (AD-1). The screens
/// are hidden from receptionists too; this is the check that can't be
/// bypassed by reaching a repository directly.
class AdminOnly implements Exception {
  const AdminOnly();

  @override
  String toString() => 'Only the owner can do this.';
}

/// Throws [AdminOnly] unless [user] is an active admin.
void requireAdmin(UserAccount user) {
  if (user.role != Role.admin || !user.isActive) throw const AdminOnly();
}
