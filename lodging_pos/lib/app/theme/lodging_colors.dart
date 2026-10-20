import 'package:flutter/material.dart';

/// The owner's palette (docs/design.md, "Colours"). Each colour has one
/// meaning: marine = navigation, primary actions and occupied beds; red =
/// overstay and urgent alerts only; butter = needs cleaning, offline and
/// warnings. Raw colour values live only in this file.
@immutable
class LodgingColors extends ThemeExtension<LodgingColors> {
  const LodgingColors({
    required this.marine,
    required this.marine600,
    required this.marineTint,
    required this.marineTintStrong,
    required this.red,
    required this.redDark,
    required this.redText,
    required this.redTint,
    required this.redBorder,
    required this.destructiveBorder,
    required this.butter,
    required this.butterBorder,
    required this.butterText,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.disabled,
    required this.line,
    required this.lineSoft,
    required this.fieldBorder,
    required this.surface,
    required this.white,
    required this.navText,
    required this.navMuted,
    required this.navActive,
    required this.syncOnline,
    required this.scrim,
    required this.brandCream,
    required this.brandGoldOnDark,
    required this.brandGoldOnLight,
  });

  static const light = LodgingColors(
    marine: Color(0xFF0B2E59),
    marine600: Color(0xFF12457F),
    marineTint: Color(0xFFEAF1FA),
    marineTintStrong: Color(0xFFF4F8FD),
    red: Color(0xFFD62839),
    redDark: Color(0xFFB01C2C),
    redText: Color(0xFF7A0F1B),
    redTint: Color(0xFFFDECEE),
    redBorder: Color(0xFFF3B7BE),
    destructiveBorder: Color(0xFFE8A0A9),
    butter: Color(0xFFF7E3A1),
    butterBorder: Color(0xFFB8962A),
    butterText: Color(0xFF3D3100),
    ink: Color(0xFF0F1B2D),
    inkSoft: Color(0xFF3A4556),
    muted: Color(0xFF5B6577),
    disabled: Color(0xFF8A93A3),
    line: Color(0xFFDDE3EC),
    lineSoft: Color(0xFFEEF1F5),
    fieldBorder: Color(0xFFC9D5E6),
    surface: Color(0xFFF5F7FA),
    white: Color(0xFFFFFFFF),
    navText: Color(0xFFE4ECF7),
    navMuted: Color(0xFFC9D8EC),
    // White at 14% (active nav item) and 12% (online sync pill).
    navActive: Color(0x24FFFFFF),
    syncOnline: Color(0x1FFFFFFF),
    // ink at 35%: dims the board behind the bed panel.
    scrim: Color(0x590F1B2D),
    // The wordmark (and the UB40 app icon): cream letters on marine with a
    // gold offset shadow; on a light ground, marine letters, brighter gold.
    brandCream: Color(0xFFF5EDD8),
    brandGoldOnDark: Color(0xFFC9962E),
    brandGoldOnLight: Color(0xFFE9B53F),
  );

  final Color marine;
  final Color marine600;
  final Color marineTint;
  final Color marineTintStrong;
  final Color red;
  final Color redDark;
  final Color redText;
  final Color redTint;
  final Color redBorder;
  final Color destructiveBorder;
  final Color butter;
  final Color butterBorder;
  final Color butterText;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color disabled;
  final Color line;
  final Color lineSoft;
  final Color fieldBorder;
  final Color surface;
  final Color white;
  final Color navText;
  final Color navMuted;
  final Color navActive;
  final Color syncOnline;
  final Color scrim;

  /// The wordmark's letters on marine.
  final Color brandCream;

  /// The wordmark's offset shadow on marine, and on a light ground.
  final Color brandGoldOnDark;
  final Color brandGoldOnLight;

  static LodgingColors of(BuildContext context) {
    final colors = Theme.of(context).extension<LodgingColors>();
    assert(colors != null, 'LodgingColors missing from the theme');
    return colors!;
  }

  /// Light theme only for the MVP, so there is nothing to vary.
  @override
  LodgingColors copyWith() => this;

  @override
  LodgingColors lerp(LodgingColors? other, double t) => this;
}
