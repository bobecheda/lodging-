import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/desk_startup.dart';
import '../../core/database/desk_startup_provider.dart';
import '../app.dart';
import '../theme/theme.dart';
import 'startup_refusal_screen.dart';

/// The desk's root (story/desk-db-guards): the app when the startup checks
/// pass, otherwise the refusal screen, which never opens the database. A
/// retry runs the checks again with [check].
class DeskRoot extends StatefulWidget {
  const DeskRoot({
    super.key,
    required this.startup,
    required this.check,
    this.app = const App(),
  });

  final DeskStartup startup;
  final Future<DeskStartup> Function() check;

  /// The app once the checks pass (tests put a stand-in here).
  final Widget app;

  @override
  State<DeskRoot> createState() => _DeskRootState();
}

class _DeskRootState extends State<DeskRoot> {
  late var _startup = widget.startup;

  Future<void> _retry() async {
    final next = await widget.check();
    if (mounted) setState(() => _startup = next);
  }

  @override
  Widget build(BuildContext context) {
    final startup = _startup;
    final overrides = [deskStartupProvider.overrideWithValue(startup)];
    if (startup.verdict is StartOk) {
      return ProviderScope(
        key: const ValueKey('desk.app'),
        overrides: overrides,
        child: widget.app,
      );
    }
    return ProviderScope(
      key: ValueKey(startup.verdict),
      overrides: overrides,
      child: MaterialApp(
        title: 'Lodging POS',
        theme: buildLodgingTheme(),
        debugShowCheckedModeBanner: false,
        home: StartupRefusalScreen(startup: startup, onRetry: _retry),
      ),
    );
  }
}
