import '../../core/audit/audit_writer.dart';
import '../../core/auth/password_hasher.dart';
import '../../core/auth/permissions.dart';
import '../../core/database/database.dart';
import '../../core/database/desk_meta.dart';
import '../../core/database/desk_startup.dart';
import '../../features/auth/data/user_repository.dart';

/// Why the start wasn't accepted.
final class UnusualStartRefused implements Exception {
  const UnusualStartRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The desk runs from a removable drive or another folder than its install
/// folder (story/desk-db-guards). The supervisor or owner may carry on with
/// their password, audited as `desk.unusual_start`; for another fixed
/// folder they may also make it the install folder. Nobody signs in here.
class UnusualStartService {
  UnusualStartService(this._db, this._audit, this._users, this._hasher);

  final AppDatabase _db;
  final AuditWriter _audit;
  final UserRepository _users;
  final PasswordHasher _hasher;

  Future<void> accept(
    UnusualLocation location, {
    required String username,
    required String password,
    required bool makeInstallFolder,
  }) async {
    final stored = await _users.findByUsername(username.trim().toLowerCase());
    final verified =
        stored != null && await _hasher.verify(password, stored.passwordHash);
    if (!verified) {
      throw const UnusualStartRefused('Wrong username or password.');
    }
    if (!can(stored.account, Permission.acceptUnusualStart)) {
      throw const UnusualStartRefused(
        'Only the supervisor or the owner can start the desk from here.',
      );
    }
    final record = makeInstallFolder && !location.removable;
    await _audit.recordEvent(
      action: 'desk.unusual_start',
      userId: stored.account.id,
      entity: 'desk',
      entityId: await _db.deviceId(),
      details: {
        'path': location.path,
        'removable': location.removable,
        'install_folder': location.recorded,
        'made_install_folder': record,
      },
    );
    if (record) await recordInstallPath(_db, location.path);
  }
}
