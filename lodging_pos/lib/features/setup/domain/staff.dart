/// Users and housekeepers (AD-4): models and rules. Pure Dart.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../auth/domain/credentials.dart';

const _maxName = 60;

String? _nameError(String name, String empty) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return empty;
  if (trimmed.length > _maxName) return 'Use at most $_maxName characters.';
  return null;
}

// ── Users ────────────────────────────────────────────────────────────────

/// The "Add a receptionist" form. The admin can add receptionists only: the
/// lodging has one admin, made at first-run setup.
final class NewReceptionist {
  const NewReceptionist({
    required this.fullName,
    required this.username,
    required this.temporaryPassword,
  });

  final String fullName;
  final String username;

  /// They must change it the first time they sign in.
  final String temporaryPassword;

  /// What gets saved: trimmed name, normalized username, password as typed.
  NewReceptionist normalized() => NewReceptionist(
    fullName: fullName.trim(),
    username: normalizeUsername(username),
    temporaryPassword: temporaryPassword,
  );
}

enum ReceptionistField { fullName, username, temporaryPassword }

/// Errors per field; empty if the receptionist can be added.
Map<ReceptionistField, String> validateNewReceptionist(
  NewReceptionist input,
) => {
  ReceptionistField.fullName: ?_nameError(
    input.fullName,
    'Enter the full name.',
  ),
  ReceptionistField.username: ?usernameError(input.username),
  ReceptionistField.temporaryPassword: ?passwordError(input.temporaryPassword),
};

enum UserStatus { active, mustSetPassword, disabled }

UserStatus userStatus(UserAccount user) {
  if (!user.isActive) return UserStatus.disabled;
  if (user.mustChangePassword) return UserStatus.mustSetPassword;
  return UserStatus.active;
}

/// A user in the list, with the time their shift opened if one is open.
final class UserSummary {
  const UserSummary(this.account, {this.shiftOpenSince});
  final UserAccount account;

  /// UTC; null when the user has no open shift.
  final DateTime? shiftOpenSince;
}

/// Why [actor] can't reset, disable or enable [target], or null. Nobody
/// changes their own account here, and an account that can itself manage
/// users (the owner today) isn't managed from this list (BR-13: decided by
/// permission, not role).
String? accountActionBlocker({
  required UserAccount actor,
  required UserAccount target,
}) {
  if (actor.id == target.id) return "You can't change your own account here.";
  if (can(target, Permission.manageUsers)) {
    return "The owner's account can't be changed here.";
  }
  return null;
}

/// Shown before disabling [user] while their shift is open. Disabling is
/// still allowed (AD-4), but in sprint 1 nobody can close that shift, so it
/// blocks the desk until FD-11 (shift close).
String? disableWarning(UserAccount user, {required DateTime? shiftOpenSince}) {
  if (shiftOpenSince == null) return null;
  final first = user.fullName.trim().split(' ').first;
  return "$first's shift is still open (since ${formatTime(shiftOpenSince)}). "
      'Until shift close exists, no other receptionist can open a shift on '
      'this desk.';
}

// ── Housekeepers ─────────────────────────────────────────────────────────

/// A housekeeper. They don't sign in; FD-9 picks them when assigning a bed.
final class Housekeeper {
  const Housekeeper({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.isActive,
  });

  final String id;
  final String fullName;

  /// 10 digits (`0722123310`), or null.
  final String? phone;
  final bool isActive;
}

enum HousekeeperField { name, phone }

/// Errors per field; empty if the housekeeper can be saved.
Map<HousekeeperField, String> housekeeperErrors({
  required String name,
  required String phone,
}) => {
  HousekeeperField.name: ?_nameError(name, 'Enter the name.'),
  HousekeeperField.phone: ?phoneError(phone),
};

/// What gets stored from the add or edit form.
final class NewHousekeeper {
  const NewHousekeeper({required this.fullName, required this.phone});

  /// Trimmed name; the phone as 10 digits, or null if left blank. Call
  /// [housekeeperErrors] first.
  factory NewHousekeeper.fromForm({
    required String name,
    required String phone,
  }) => NewHousekeeper(
    fullName: name.trim(),
    phone: phone.trim().isEmpty ? null : normalizePhone(phone),
  );

  final String fullName;
  final String? phone;
}
