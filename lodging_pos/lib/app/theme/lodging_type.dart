import 'package:flutter/material.dart';

import 'lodging_colors.dart';

/// Font families bundled in pubspec.yaml. Used only in lib/app/theme/.
const manrope = 'Manrope';
const plexMono = 'IBMPlexMono';

/// The wordmark: the lodging name in Pirata One, "Lodging" under it in
/// IM Fell English SC. A logo, not interface text: outside the type scale.
const pirataOne = 'PirataOne';
const imFellEnglishSc = 'IMFellEnglishSC';

/// The v2 type scale (docs/design-system.md, "Type"): Manrope for the
/// interface, IBM Plex Mono for money, receipt numbers, M-Pesa codes and
/// counts. Hierarchy comes from size and space, not boldness: weights 400,
/// 500 and 600 only, nothing below 12, no caps labels (sentence case).
/// Font sizes live only in this file.
@immutable
class LodgingType extends ThemeExtension<LodgingType> {
  const LodgingType({
    required this.pageTitle,
    required this.sectionTitle,
    required this.body,
    required this.bodyMedium,
    required this.secondary,
    required this.secondaryMedium,
    required this.meta,
    required this.moneyHero,
    required this.money,
    required this.moneySmall,
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
      pageTitle: ui(24, FontWeight.w600, c.ink, h: 1.2),
      sectionTitle: ui(18, FontWeight.w600, c.ink, h: 1.3),
      body: ui(16, FontWeight.w400, c.ink, h: 1.45),
      bodyMedium: ui(16, FontWeight.w500, c.ink, h: 1.45),
      secondary: ui(14, FontWeight.w400, c.muted, h: 1.4),
      secondaryMedium: ui(14, FontWeight.w500, c.ink, h: 1.4),
      meta: ui(12, FontWeight.w500, c.muted, h: 1.4),
      moneyHero: mono(30, FontWeight.w600),
      money: mono(18, FontWeight.w600),
      moneySmall: mono(14, FontWeight.w500),
    );
  }

  /// 24/600. The page's one heading, only when it doesn't repeat the tab.
  final TextStyle pageTitle;

  /// 18/600. Card and section headings.
  final TextStyle sectionTitle;

  /// 16/400. Values and running text.
  final TextStyle body;

  /// 16/500. Names and values that lead a row.
  final TextStyle bodyMedium;

  /// 14/400 muted. Secondary text and captions.
  final TextStyle secondary;

  /// 14/500. Field labels, buttons, tabs, small headings.
  final TextStyle secondaryMedium;

  /// 12/500 muted. Meta only: times, counts, status labels.
  final TextStyle meta;

  /// Mono 30/600. The one hero figure on a screen.
  final TextStyle moneyHero;

  /// Mono 18/600. Money in inputs and totals.
  final TextStyle money;

  /// Mono 14/500. Receipt numbers, M-Pesa codes, money in rows.
  final TextStyle moneySmall;

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
