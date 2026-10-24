import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/owner_app/presentation/owner_app.dart';

/// The owner's phone app (Android and web): `flutter run -t
/// lib/main_owner.dart --dart-define-from-file=secrets.json`. It never
/// imports the desk's database or sync (test/policy/owner_app_test.dart).
void main() {
  runApp(const ProviderScope(child: OwnerApp()));
}
