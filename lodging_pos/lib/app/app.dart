import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_detector.dart';
import 'router.dart';
import 'theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Lodging POS',
    theme: appTheme,
    routerConfig: ref.watch(routerProvider),
    // Above the navigator, so activity on every screen and dialog counts.
    builder: (context, child) => ActivityDetector(child: child!),
  );
}
