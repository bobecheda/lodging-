import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'password_hasher.g.dart';

/// bcrypt hashing. The bcrypt package is pure Dart and synchronous, so work
/// runs on a separate isolate to keep the UI responsive.
class PasswordHasher {
  const PasswordHasher({this.logRounds = 10, this.useIsolate = true});

  /// Tests use a low cost and no isolate.
  const PasswordHasher.fast() : logRounds = 4, useIsolate = false;

  final int logRounds;
  final bool useIsolate;

  Future<String> hash(String password) {
    final rounds = logRounds;
    return _run(
      () => BCrypt.hashpw(password, BCrypt.gensalt(logRounds: rounds)),
    );
  }

  Future<bool> verify(String password, String hash) =>
      _run(() => BCrypt.checkpw(password, hash));

  Future<R> _run<R>(R Function() work) =>
      useIsolate ? Isolate.run(work) : Future.sync(work);
}

@Riverpod(keepAlive: true)
PasswordHasher passwordHasher(Ref ref) => const PasswordHasher();
