/// What the owner's phone asks of the cloud: sign-in, plain reads with an
/// explicit column list, and the cloud functions. The phone has no database
/// of its own; whatever it loads lives in memory only (docs/sync.md, "The
/// owner's phone").
library;

/// A filter on one column.
sealed class Where {
  const Where(this.column);
  final String column;
}

final class Eq extends Where {
  const Eq(super.column, this.value);
  final Object value;
}

/// At or after / at least [value].
final class Gte extends Where {
  const Gte(super.column, this.value);
  final Object value;
}

final class IsNull extends Where {
  const IsNull(super.column);
}

final class InList extends Where {
  const InList(super.column, this.values);
  final List<Object> values;
}

/// The owner, signed in: their desk account's id (`users.id`, from the
/// sign-in's `app_metadata.user_id`) and their email.
final class OwnerSignIn {
  const OwnerSignIn({required this.userId, required this.email});
  final String userId;
  final String email;
}

/// The cloud can't be reached (no internet, a timeout).
final class OwnerCloudOffline implements Exception {
  const OwnerCloudOffline(this.detail);
  final String detail;
  @override
  String toString() => 'OwnerCloudOffline: $detail';
}

/// The cloud refused: [message] is safe to show.
final class OwnerCloudRefused implements Exception {
  const OwnerCloudRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The sign-in was refused, or the session can no longer be renewed (the
/// password was changed elsewhere, or the account was signed out).
final class OwnerSignInRefused implements Exception {
  const OwnerSignInRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class OwnerCloud {
  /// The sign-in kept from last time, if any (no network needed).
  Future<OwnerSignIn?> restore();

  /// Signs the owner in; refuses any account that isn't the owner's.
  Future<OwnerSignIn> signIn({required String email, required String password});

  /// Forgets the sign-in on this phone.
  Future<void> signOut();

  /// The rows of [table] matching every filter in [where], with only
  /// [columns] (never `*`), ordered by [orderBy] when given (latest first
  /// with [newestFirst]). All pages, or the first [limit] rows.
  Future<List<Map<String, Object?>>> rows(
    String table,
    List<String> columns, {
    List<Where> where = const [],
    String? orderBy,
    bool newestFirst = false,
    int? limit,
  });

  /// Checks [password] is the signed-in owner's (by signing in again).
  /// Throws [OwnerSignInRefused] or [OwnerCloudOffline].
  Future<void> verifyPassword(String password);

  /// Sets the signed-in owner's password.
  Future<void> updatePassword(String password);

  /// Ends the owner's other sessions (the desk's owner sign-in); this
  /// phone stays signed in, and the desk's own sign-in is untouched.
  Future<void> signOutOtherSessions();

  /// Calls the cloud function [name].
  Future<Object?> rpc(String name, Map<String, Object?> params);

  /// This install's id, made once and kept on the phone: the `device_id`
  /// of what the owner writes from here.
  Future<String> deviceId();
}
