import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud.dart';

/// Where the desk keeps its cloud sign-in. On Windows the secret is
/// encrypted with a key held in the signed-in Windows user's Credential
/// Manager, so the desk must always run under the same Windows user; under
/// another user the secret is missing and the owner uses "Reconnect this
/// desk" (docs/sync.md).
abstract interface class DeskSecretStore {
  Future<DeskCredentials?> read();
  Future<void> write(DeskCredentials credentials);
  Future<void> delete();
}

class SecureDeskSecretStore implements DeskSecretStore {
  SecureDeskSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _email = 'lodging_pos.desk_email';
  static const _secret = 'lodging_pos.desk_secret';

  @override
  Future<DeskCredentials?> read() async {
    final email = await _storage.read(key: _email);
    final secret = await _storage.read(key: _secret);
    if (email == null || secret == null) return null;
    return DeskCredentials(email: email, secret: secret);
  }

  @override
  Future<void> write(DeskCredentials credentials) async {
    await _storage.write(key: _email, value: credentials.email);
    await _storage.write(key: _secret, value: credentials.secret);
  }

  @override
  Future<void> delete() async {
    await _storage.delete(key: _email);
    await _storage.delete(key: _secret);
  }
}

/// Kept in memory only: tests, and builds without secure storage.
class MemoryDeskSecretStore implements DeskSecretStore {
  DeskCredentials? credentials;

  @override
  Future<DeskCredentials?> read() async => credentials;

  @override
  Future<void> write(DeskCredentials credentials) async =>
      this.credentials = credentials;

  @override
  Future<void> delete() async => credentials = null;
}
