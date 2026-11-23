import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A route over the current screen for the shell's menus, the menu drawer
/// and the side panels (docs/design-system.md, "Motion"): its own in and
/// out durations, a scrim that fades on its own (shorter) time, Escape or
/// a tap outside closes it, and focus stays inside while it's open (a
/// route's focus scope). Only opacity and transform animate.
class ShellOverlayRoute<T> extends PopupRoute<T> {
  ShellOverlayRoute({
    required this.builder,
    required this.transition,
    required Duration inDuration,
    required Duration outDuration,
    required Duration scrimDuration,
    required this.label,
    this.scrim,
  }) : _in = inDuration,
       _out = outDuration,
       _scrimShare = inDuration == Duration.zero
           ? 1
           : (scrimDuration.inMicroseconds / inDuration.inMicroseconds).clamp(
               0.0,
               1.0,
             );

  final WidgetBuilder builder;

  /// Moves and fades the page in and out ([animation] runs 0 → 1 in).
  final Widget Function(Animation<double> animation, Widget child) transition;
  final Duration _in;
  final Duration _out;
  final double _scrimShare;
  final String label;

  /// The dimmed screen behind (null: clear, as behind a menu).
  final Color? scrim;

  @override
  Color? get barrierColor => scrim;

  @override
  Curve get barrierCurve => Interval(0, _scrimShare);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => _in;

  @override
  Duration get reverseTransitionDuration => _out;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => transition(animation, child);
}

/// Slides the page in from [from] (−1: from the left edge, 1: from the
/// right) on [inStep]'s curve, and out on [outStep]'s. Reduced motion
/// gives zero durations, so it is instant.
Widget Function(Animation<double>, Widget) slideFrom(
  double from,
  MotionStep inStep,
  MotionStep outStep,
) => (animation, child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: inStep.curve,
    reverseCurve: outStep.curve.flipped,
  );
  return SlideTransition(
    position: Tween(begin: Offset(from, 0), end: Offset.zero).animate(curved),
    child: child,
  );
};
