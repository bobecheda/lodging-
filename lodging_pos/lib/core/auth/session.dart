import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'user_account.dart';

part 'session.g.dart';

/// The signed-in user, held in memory only. Null when signed out.
@Riverpod(keepAlive: true)
class Session extends _$Session {
  @override
  UserAccount? build() => null;

  void signIn(UserAccount user) => state = user;

  /// The shift stays open; only the session ends.
  void signOut() => state = null;

  void passwordChanged() => state = state?.copyWith(mustChangePassword: false);
}
