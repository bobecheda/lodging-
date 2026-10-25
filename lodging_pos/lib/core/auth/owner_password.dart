/// The owner's password is also their cloud sign-in (owner-app-3,
/// docs/sync.md "The owner's password"): every change is recorded in the
/// cloud first (`owner_password_changes`), and the desk, which keeps its own
/// copy for signing in offline, follows a change made on the phone. Pure
/// Dart, used by the desk's sync and sign-in.
library;

/// The desk refuses its own copy of the owner's password: the cloud
/// recorded a change after the desk last caught up ([cloudAt] from the
/// pull, [deskAt] when the desk's copy was last brought up to date; both
/// the server's times).
bool ownerPasswordBehind({
  required DateTime? cloudAt,
  required DateTime? deskAt,
}) => cloudAt != null && (deskAt == null || cloudAt.isAfter(deskAt));

/// Shown at sign-in while the desk's copy is behind and the cloud can't
/// confirm the password (offline, or not the new one).
const passwordChangedOnPhone =
    'Your password was changed on your phone. Sign in with the new one '
    '(needs internet).';

/// The owner's password changes in the cloud first: offline it is refused.
const changingPasswordNeedsInternet =
    'Changing your password needs an internet connection.';
