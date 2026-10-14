enum Role {
  admin,
  receptionist;

  static Role parse(String value) => values.firstWhere((r) => r.name == value);
}

/// A user as the app sees it. The password hash never leaves the data layer.
class UserAccount {
  const UserAccount({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.isActive,
    required this.mustChangePassword,
  });

  final String id;
  final String fullName;
  final String username;
  final Role role;
  final bool isActive;
  final bool mustChangePassword;

  UserAccount copyWith({bool? isActive, bool? mustChangePassword}) =>
      UserAccount(
        id: id,
        fullName: fullName,
        username: username,
        role: role,
        isActive: isActive ?? this.isActive,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );
}
