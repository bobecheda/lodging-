import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/theme.dart';

/// How a page inside the shell arrives (docs/design-system.md, "Motion").
enum PageKind {
  /// A tab's page: the old one fades out (120 ms), then the new one fades
  /// in rising 8 px (180 ms).
  tab,

  /// A flow opened from a page (check-in, a drawer count, a decision): it
  /// slides 16 px in from the right as it fades in (250 ms), and back out
  /// the same way (200 ms).
  flow,
}

/// A page with the shell's transition. Only opacity and transform move;
/// the top bar sits outside the pages, so it never does. With reduced
/// motion the new page shows at once and the old one goes at once.
Page<void> deskPage(
  GoRouterState state,
  Widget child, {
  PageKind kind = PageKind.tab,
}) {
  const m = LodgingMotion.standard;
  final (inTime, outTime) = switch (kind) {
    PageKind.tab => (m.tabOut.duration + m.tabIn.duration, m.tabOut.duration),
    PageKind.flow => (m.flowIn.duration, m.flowBack.duration),
  };
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: inTime,
    reverseTransitionDuration: outTime,
    transitionsBuilder: (context, animation, _, child) {
      if (LodgingMotion.of(context).reduced) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Threshold(0),
            reverseCurve: const Threshold(1),
          ),
          child: child,
        );
      }
      return switch (kind) {
        PageKind.tab => _TabTransition(animation: animation, child: child),
        PageKind.flow => _FlowTransition(animation: animation, child: child),
      };
    },
  );
}

class _TabTransition extends StatelessWidget {
  const _TabTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const m = LodgingMotion.standard;
    final outShare =
        m.tabOut.duration.inMicroseconds /
        (m.tabOut.duration + m.tabIn.duration).inMicroseconds;
    // In: wait for the old page to fade, then fade in and rise.
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(outShare, 1, curve: m.tabIn.curve),
      reverseCurve: m.tabOut.curve.flipped,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final leaving = animation.status == AnimationStatus.reverse;
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, leaving ? 0 : m.tabRise * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _FlowTransition extends StatelessWidget {
  const _FlowTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const m = LodgingMotion.standard;
    final curved = CurvedAnimation(
      parent: animation,
      curve: m.flowIn.curve,
      reverseCurve: m.flowBack.curve.flipped,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(m.flowSlide * (1 - curved.value), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A focused flow outside the shell (brief: "Focused flows (close shift,
/// sign-in) have no navigation"): the page alone on the app background,
/// centred, at most [maxWidth] wide.
class FocusedFlow extends StatelessWidget {
  const FocusedFlow({super.key, required this.child, this.maxWidth = 568});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LodgingColors.of(context).surface,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x24,
              vertical: Space.x32,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
