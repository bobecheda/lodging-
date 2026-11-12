import 'package:flutter/widgets.dart';

/// One animated step: how long and with which curve.
@immutable
class MotionStep {
  const MotionStep(this.duration, this.curve);

  final Duration duration;
  final Curve curve;
}

/// Motion tokens (docs/design-system.md, "Motion"). Motion explains, never
/// decorates: only opacity and transform animate, the top bar never moves,
/// input is never blocked. Read with [LodgingMotion.of], which honours
/// reduced motion (Windows "Show animations" off reaches Flutter as
/// `MediaQuery.disableAnimations`): every step becomes instant and every
/// offset zero.
@immutable
class LodgingMotion {
  const LodgingMotion._({
    required this.reduced,
    required this.tabIndicator,
    required this.tabOut,
    required this.tabIn,
    required this.tabRise,
    required this.flowIn,
    required this.flowBack,
    required this.flowSlide,
    required this.menuOpen,
    required this.menuClose,
    required this.menuDrop,
    required this.panel,
    required this.scrim,
    required this.count,
  });

  /// The brief's tokens.
  static const standard = LodgingMotion._(
    reduced: false,
    tabIndicator: MotionStep(Duration(milliseconds: 200), Curves.easeOut),
    tabOut: MotionStep(Duration(milliseconds: 120), Curves.easeIn),
    tabIn: MotionStep(Duration(milliseconds: 180), Curves.easeOut),
    tabRise: 8,
    flowIn: MotionStep(Duration(milliseconds: 250), Curves.easeOut),
    flowBack: MotionStep(Duration(milliseconds: 200), Curves.easeIn),
    flowSlide: 16,
    menuOpen: MotionStep(Duration(milliseconds: 150), Curves.easeOut),
    menuClose: MotionStep(Duration(milliseconds: 120), Curves.easeIn),
    menuDrop: 4,
    panel: MotionStep(Duration(milliseconds: 220), Curves.easeOut),
    scrim: MotionStep(Duration(milliseconds: 150), Curves.linear),
    count: MotionStep(Duration(milliseconds: 150), Curves.linear),
  );

  /// Reduced motion: everything switches at once, nothing moves.
  static const instant = LodgingMotion._(
    reduced: true,
    tabIndicator: MotionStep(Duration.zero, Curves.linear),
    tabOut: MotionStep(Duration.zero, Curves.linear),
    tabIn: MotionStep(Duration.zero, Curves.linear),
    tabRise: 0,
    flowIn: MotionStep(Duration.zero, Curves.linear),
    flowBack: MotionStep(Duration.zero, Curves.linear),
    flowSlide: 0,
    menuOpen: MotionStep(Duration.zero, Curves.linear),
    menuClose: MotionStep(Duration.zero, Curves.linear),
    menuDrop: 0,
    panel: MotionStep(Duration.zero, Curves.linear),
    scrim: MotionStep(Duration.zero, Curves.linear),
    count: MotionStep(Duration.zero, Curves.linear),
  );

  /// True when the system asked for reduced motion.
  final bool reduced;

  /// The tab indicator sliding to the new tab.
  final MotionStep tabIndicator;

  /// The old tab's content fading out, and the new one fading in.
  final MotionStep tabOut;
  final MotionStep tabIn;

  /// How far the new tab's content rises as it fades in (px).
  final double tabRise;

  /// Opening a flow (check-in, a drawer count, a decision), and going back.
  final MotionStep flowIn;
  final MotionStep flowBack;

  /// How far a flow slides in the direction of travel (px).
  final double flowSlide;

  /// A menu (Setup ▾, the 768 menu) opening and closing.
  final MotionStep menuOpen;
  final MotionStep menuClose;

  /// How far a menu drops from its tab (px).
  final double menuDrop;

  /// The bed panel sliding in from the right, and its scrim fading.
  final MotionStep panel;
  final MotionStep scrim;

  /// A count or badge cross-fading to its new number.
  final MotionStep count;

  static LodgingMotion of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? instant
      : standard;
}
