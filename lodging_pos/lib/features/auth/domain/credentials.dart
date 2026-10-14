/// Usernames are stored trimmed and lowercase, so uniqueness and login are
/// case-insensitive (the database CHECKs the stored form).
String normalizeUsername(String input) => input.trim().toLowerCase();

final _usernamePattern = RegExp(r'^[a-z0-9._-]{3,32}$');

/// Null if valid. Checks the normalized form.
String? usernameError(String input) {
  final username = normalizeUsername(input);
  if (username.isEmpty) return 'Enter a username';
  if (!_usernamePattern.hasMatch(username)) {
    return '3–32 characters: letters, digits, dot, underscore or dash';
  }
  return null;
}

const minPasswordLength = 8;

/// Null if valid. Length only; no complexity rules.
String? passwordError(String password) {
  if (password.isEmpty) return 'Enter a password';
  if (password.length < minPasswordLength) {
    return 'At least $minPasswordLength characters';
  }
  return null;
}

enum PasswordField { password, confirm }

/// Errors for a new password and its confirmation; empty if both are valid.
Map<PasswordField, String> newPasswordErrors(String password, String confirm) {
  final error = passwordError(password);
  if (error != null) return {PasswordField.password: error};
  if (password != confirm) {
    return {PasswordField.confirm: 'Passwords do not match'};
  }
  return const {};
}
