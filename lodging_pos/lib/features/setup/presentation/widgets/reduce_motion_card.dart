import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/settings/reduce_motion.dart';

/// "Reduce motion" for this desk PC (v2 PR 3), beside the supervisor's
/// settings: on, every animation switches at once.
class ReduceMotionCard extends ConsumerStatefulWidget {
  const ReduceMotionCard({super.key});

  @override
  ConsumerState<ReduceMotionCard> createState() => _ReduceMotionCardState();
}

class _ReduceMotionCardState extends ConsumerState<ReduceMotionCard> {
  var _busy = false;

  Future<void> _set(bool on) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(reduceMotionSettingProvider).set(user, on: on);
      ref.invalidate(reduceMotionProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final on = ref.watch(reduceMotionProvider).value ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x24,
          vertical: Space.x12,
        ),
        child: MergeSemantics(
          child: Row(
            children: [
              Expanded(child: Text('Reduce motion', style: t.bodyMedium)),
              Switch(
                key: const ValueKey('settings.reduceMotion'),
                value: on,
                onChanged: _busy ? null : _set,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
