import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/schema_check.dart';
import 'theme/theme.dart';
import 'widgets/buttons.dart';
import 'widgets/notes.dart';

/// The database file doesn't match this build. A debug build offers to reset
/// it, keeping the old file as a backup; a release build only explains and
/// never offers to throw data away.
class OldDatabaseScreen extends ConsumerStatefulWidget {
  const OldDatabaseScreen({super.key});

  @override
  ConsumerState<OldDatabaseScreen> createState() => _OldDatabaseScreenState();
}

class _OldDatabaseScreenState extends ConsumerState<OldDatabaseScreen> {
  static const _shown = 8;
  var _busy = false;
  String? _error;

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(resetTestDatabaseProvider)();
      // A fresh database: check again, then the app goes to first-run setup.
      ref.invalidate(schemaDriftProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final canReset = ref.watch(canResetDatabaseProvider);
    final differences =
        ref.watch(schemaDriftProvider).value?.differences ?? const [];
    final more = differences.length - _shown;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.x32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        canReset
                            ? 'This test database was made by an older build'
                            : 'The database does not match this version',
                        style: t.sectionTitle,
                      ),
                    ),
                    const SizedBox(height: Space.x12),
                    Text(
                      canReset
                          ? 'Its tables differ from what this build creates, '
                                'so screens would fail. Reset it to start '
                                'fresh: you will set up the lodging again, and '
                                'the old file is kept as a backup next to the '
                                'new one.'
                          : 'The app has stopped so that nothing is saved '
                                'wrongly. Your data is untouched. Do not use '
                                'this PC for the desk until support has '
                                'checked it, and tell them what is listed '
                                'below.',
                      style: t.body,
                    ),
                    const SizedBox(height: Space.x16),
                    Container(
                      padding: const EdgeInsets.all(Space.x12),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final d in differences.take(_shown))
                            Text(d, style: t.mono),
                          if (more > 0) Text('and $more more', style: t.small),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.x16),
                      Note.error(_error!, title: 'The reset failed.'),
                    ],
                    if (canReset) ...[
                      const SizedBox(height: Space.x20),
                      AppButton.destructive(
                        key: const ValueKey('oldDatabase.reset'),
                        label: 'Reset test database',
                        busy: _busy,
                        onPressed: _reset,
                      ),
                      const SizedBox(height: Space.x12),
                      Text(
                        'Only debug builds offer a reset. A release build '
                        'never throws data away.',
                        style: t.small.copyWith(color: c.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
