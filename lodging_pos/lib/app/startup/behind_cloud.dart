import '../../core/app_version.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/auth/password_hasher.dart';
import '../../core/auth/permissions.dart';
import '../../core/clock/nairobi.dart';
import '../../core/database/database.dart';
import '../../core/sync/desk_behind.dart';
import '../../features/auth/data/user_repository.dart';

/// Why the details weren't shown.
final class BehindDetailsRefused implements Exception {
  const BehindDetailsRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The refusal screen's owner-only step (story/desk-db-guards-2): with the
/// owner's username and password, what proved this PC's data older than
/// the cloud, and the text to copy for the technician. Audited
/// `desk.behind_details`. It unlocks nothing; nobody signs in here.
class BehindDetailsService {
  BehindDetailsService(this._db, this._audit, this._users, this._hasher);

  final AppDatabase _db;
  final AuditWriter _audit;
  final UserRepository _users;
  final PasswordHasher _hasher;

  /// The text for the technician; throws [BehindDetailsRefused].
  Future<String> reveal(
    BehindEvidence evidence, {
    required String username,
    required String password,
  }) async {
    final stored = await _users.findByUsername(username.trim().toLowerCase());
    final verified =
        stored != null &&
        stored.account.isActive &&
        await _hasher.verify(password, stored.passwordHash);
    if (!verified) {
      throw const BehindDetailsRefused('Wrong username or password.');
    }
    if (!can(stored.account, Permission.viewBehindEvidence)) {
      throw const BehindDetailsRefused('Only the owner can see the details.');
    }
    final device = await _db.deviceId();
    await _audit.recordEvent(
      action: 'desk.behind_details',
      userId: stored.account.id,
      entity: 'sync',
      entityId: device,
      details: {'found_at': evidence.foundAt.toUtc().toIso8601String()},
    );
    return behindCopyText(
      evidence,
      deviceId: device,
      version: versionLine(
        AppBuild.current,
        schemaVersion: latestSchemaVersion,
      ),
    );
  }
}

/// What the owner copies for the technician: which desk, when it was found, each
/// proof, and this app's version. No guest data, no phone numbers.
String behindCopyText(
  BehindEvidence evidence, {
  required String deviceId,
  required String version,
}) => [
  'Desk ${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}: '
      'this PC’s data is older than the cloud (found '
      '${formatDayDateTime(evidence.foundAt)}).',
  for (final line in evidence.lines()) '- $line',
  'This app: $version.',
].join('\n');
