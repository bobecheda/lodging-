import 'package:flutter/material.dart';

import 'lodging_colors.dart';

/// Font families bundled in pubspec.yaml. Used only in lib/app/theme/.
const manrope = 'Manrope';
const plexMono = 'IBMPlexMono';

/// Type scale (docs/design.md, "Typography"): Manrope for the interface,
/// IBM Plex Mono for receipt numbers, M-Pesa codes, money and counts. Font
/// sizes live only in this file. Minimum 12, except caps labels at 11.
@immutable
class LodgingType extends ThemeExtension<LodgingType> {
  const LodgingType({
    required this.pageTitle,
    required this.heroTitle,
    required this.cardTitle,
    required this.sectionTitle,
    required this.cardHeading,
    required this.capsLabel,
    required this.body,
    required this.bodyStrong,
    required this.small,
    required this.smallStrong,
    required this.fieldLabel,
    required this.button,
    required this.nav,
    required this.mono,
    required this.monoStrong,
    required this.moneyLarge,
    required this.moneyHero,
    required this.stepperValue,
  });

  factory LodgingType.from(LodgingColors c) {
    TextStyle ui(double size, FontWeight weight, Color color, {double? h}) =>
        TextStyle(
          fontFamily: manrope,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: h,
        );
    TextStyle mono(double size, FontWeight weight) => TextStyle(
      fontFamily: plexMono,
      fontSize: size,
      fontWeight: weight,
      color: c.ink,
    );
    return LodgingType(
      pageTitle: ui(24, FontWeight.w800, c.ink, h: 1.2),
      heroTitle: ui(36, FontWeight.w800, c.ink, h: 1.15),
      cardTitle: ui(28, FontWeight.w800, c.ink, h: 1.2),
      sectionTitle: ui(17, FontWeight.w800, c.ink, h: 1.3),
      cardHeading: ui(
        13,
        FontWeight.w800,
        c.muted,
      ).copyWith(letterSpacing: 13 * 0.06),
      capsLabel: ui(
        11,
        FontWeight.w800,
        c.muted,
      ).copyWith(letterSpacing: 11 * 0.06),
      body: ui(14, FontWeight.w500, c.ink, h: 1.45),
      bodyStrong: ui(14, FontWeight.w700, c.ink, h: 1.45),
      small: ui(13, FontWeight.w500, c.muted, h: 1.4),
      smallStrong: ui(12, FontWeight.w700, c.muted, h: 1.4),
      fieldLabel: ui(13, FontWeight.w700, c.ink),
      button: ui(15, FontWeight.w800, c.white),
      nav: ui(14, FontWeight.w600, c.navText),
      mono: mono(13, FontWeight.w500),
      monoStrong: mono(14, FontWeight.w600),
      moneyLarge: mono(22, FontWeight.w600),
      moneyHero: mono(30, FontWeight.w600),
      stepperValue: mono(22, FontWeight.w600),
    );
  }

  /// 24/800. One per page.
  final TextStyle pageTitle;

  /// Large brand-panel heading ("Front desk").
  final TextStyle heroTitle;

  /// Greeting on a centred card ("Good morning, Mary").
  final TextStyle cardTitle;

  /// 17/800.
  final TextStyle sectionTitle;

  /// 13/800 caps, 0.06em tracking, muted. Pass text already in capitals.
  final TextStyle cardHeading;

  /// 11/800 caps for status labels (READY, IN USE…).
  final TextStyle capsLabel;
  final TextStyle body;
  final TextStyle bodyStrong;

  /// 13/500 muted: captions, helper text.
  final TextStyle small;
  final TextStyle smallStrong;

  /// 13/700, above inputs.
  final TextStyle fieldLabel;
  final TextStyle button;
  final TextStyle nav;

  /// Receipt numbers, M-Pesa codes, small counts.
  final TextStyle mono;
  final TextStyle monoStrong;

  /// Money in inputs and totals (22).
  final TextStyle moneyLarge;

  /// The biggest money figure on a screen (30).
  final TextStyle moneyHero;
  final TextStyle stepperValue;

  static LodgingType of(BuildContext context) {
    final type = Theme.of(context).extension<LodgingType>();
    assert(type != null, 'LodgingType missing from the theme');
    return type!;
  }

  @override
  LodgingType copyWith() => this;

  @override
  LodgingType lerp(LodgingType? other, double t) => this;
}
