import 'credentials.dart';

/// The first-run "Set up this lodging" form: the owner's account plus the
/// lodging name that receipts print. A database from before the owner role
/// uses it without the lodging name ("Create the owner's account").

/// Where first-run setup stands.
enum SetupState {
  /// No users: first run creates the owner and names the lodging.
  fresh,

  /// Users, but no owner (a database from before the owner role): the
  /// owner's account must be created before anyone signs in.
  needsOwner,

  /// Done: sign-in.
  ready,
}

class SetupInput {
  const SetupInput({
    required this.fullName,
    required this.username,
    required this.password,
    required this.confirmPassword,
    required this.lodgingName,
  });

  final String fullName;
  final String username;
  final String password;
  final String confirmPassword;
  final String lodgingName;

  SetupInput copyWith({
    String? fullName,
    String? username,
    String? password,
    String? confirmPassword,
    String? lodgingName,
  }) => SetupInput(
    fullName: fullName ?? this.fullName,
    username: username ?? this.username,
    password: password ?? this.password,
    confirmPassword: confirmPassword ?? this.confirmPassword,
    lodgingName: lodgingName ?? this.lodgingName,
  );

  /// What gets saved: trimmed names, normalized username. Passwords are
  /// kept exactly as typed.
  SetupInput normalized() => copyWith(
    fullName: fullName.trim(),
    username: normalizeUsername(username),
    lodgingName: lodgingName.trim(),
  );
}

enum SetupField { fullName, username, password, confirmPassword, lodgingName }

/// Errors per field; empty if the form can be saved. Without
/// [withLodgingName] (creating the owner on a database that has one), the
/// lodging name isn't asked for.
Map<SetupField, String> validateSetup(
  SetupInput input, {
  bool withLodgingName = true,
}) {
  final errors = <SetupField, String>{};
  if (input.fullName.trim().isEmpty) {
    errors[SetupField.fullName] = 'Enter your full name';
  }
  final usernameProblem = usernameError(input.username);
  if (usernameProblem != null) errors[SetupField.username] = usernameProblem;
  for (final MapEntry(:key, :value) in newPasswordErrors(
    input.password,
    input.confirmPassword,
  ).entries) {
    errors[switch (key) {
          PasswordField.password => SetupField.password,
          PasswordField.confirm => SetupField.confirmPassword,
        }] =
        value;
  }
  if (withLodgingName && input.lodgingName.trim().isEmpty) {
    errors[SetupField.lodgingName] = 'Enter the lodging name';
  }
  return errors;
}
