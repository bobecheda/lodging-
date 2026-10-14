import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/idle_lock.dart';

/// Wraps the whole app and reports every click, scroll, key press and mouse
/// movement to [IdleLock], so no screen has to remember to.
class ActivityDetector extends ConsumerStatefulWidget {
  const ActivityDetector({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ActivityDetector> createState() => _ActivityDetectorState();
}

class _ActivityDetectorState extends ConsumerState<ActivityDetector> {
  late final IdleLock _lock = ref.read(idleLockProvider.notifier);

  bool _onKey(KeyEvent event) {
    _lock.recordActivity();
    return false; // Never consume the key.
  }

  void _onPointer(PointerEvent _) => _lock.recordActivity();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointer,
    onPointerMove: _onPointer,
    onPointerHover: _onPointer,
    onPointerSignal: _onPointer, // scroll wheel
    onPointerPanZoomUpdate: _onPointer, // trackpad scroll
    child: widget.child,
  );
}
