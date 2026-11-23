import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

/// Runs before every test file: the bundled fonts are loaded once, outside
/// the tests' fake time, so widget tests measure text as the desk does (the
/// top bar's tabs fit at 1366, as on the real desk).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  await testMain();
}
