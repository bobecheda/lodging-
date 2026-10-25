import '../../../core/auth/owner_password.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/sync/cloud_writes.dart';
import '../domain/credentials.dart';
import 'user_repository.dart';

/// The owner's "Change my password" was refused; [message] is shown.
final class PasswordChangeRefused implements Exception {
  const PasswordChangeRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The owner changes their own password on the desk (owner-app-3). Once
/// this desk is connected it is also the owner's cloud sign-in, so it
/// changes in the cloud first (recorded, then set) and only then here;
/// offline it is refused and nothing changes. Before connecting, it changes
/// here only, as any password.
class OwnerPasswordService {
  OwnerPasswordService(this._users, this._hasher, {this._cloud});

  final UserRepository _users;
  final PasswordHasher _hasher;
  final OwnerPasswordCloud? _cloud;

  /// Throws [PasswordChangeRefused] or [NotPermitted].
  Future<void> change(
    UserAccount owner, {
    required String current,
    required String next,
  }) async {
    requirePermission(owner, Permission.ownerCloudPassword);
    final problem = passwordError(next);
    if (problem != null) throw PasswordChangeRefused(problem);
    if (next == current) {
      throw const PasswordChangeRefused(
        'Choose a password different from the current one.',
      );
    }
    final stored = await _users.findByUsername(owner.username);
    if (stored == null || !await _hasher.verify(current, stored.passwordHash)) {
      throw const PasswordChangeRefused('That isn’t your current password.');
    }
    final cloud = _cloud;
    if (cloud == null || !cloud.active) {
      await _users.changePassword(owner.id, next);
      return;
    }
    final DateTime at;
    try {
      at = await cloud.changeOwnerPassword(current: current, next: next);
    } on NeedsInternet {
      throw const PasswordChangeRefused(changingPasswordNeedsInternet);
    } on OwnerPasswordRefused {
      throw const PasswordChangeRefused(
        'The cloud doesn’t accept your current password. If you changed it '
        'on your phone, lock the screen and sign in with that one.',
      );
    } on CloudWriteRefused catch (e) {
      throw PasswordChangeRefused(
        cloudRefusalMessage(e, needsInternet: changingPasswordNeedsInternet),
      );
    }
    await _users.changePassword(owner.id, next);
    await cloud.ownerPasswordChangedHere(at);
  }
}
