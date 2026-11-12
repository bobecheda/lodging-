import 'package:flutter/material.dart';

/// The palette (docs/design-system.md, "Colour"; v2). Each colour has one
/// meaning: marine = brand and action; marine-tint = occupied (quiet) and
/// selected; red = overstay and urgent only; butter = needs cleaning,
/// warnings, count badges and offline; green = good; each room category
/// has its own colour key ([categories]). Raw colour values live only in
/// this file.
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
    required this.green,
    required this.greenTint,
    required this.butterTint,
    required this.categories,
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
    // Good: online, money up, count matched, saved.
    green: Color(0xFF1E7B4F),
    greenTint: Color(0xFFE6F4EC),
    // Soft warning background (Figma status/butter-tint).
    butterTint: Color(0xFFFDF6DE),
    // Room categories, in the order new categories take them. The stripe
    // needs 3:1 on white, the label text 4.5:1.
    categories: [
      CategorySwatch(
        'gold',
        stripe: Color(0xFFB8862B),
        text: Color(0xFF7A5A12),
      ),
      CategorySwatch(
        'violet',
        stripe: Color(0xFF5B4B9A),
        text: Color(0xFF5B4B9A),
      ),
      CategorySwatch(
        'teal',
        stripe: Color(0xFF1F7A86),
        text: Color(0xFF1F7A86),
      ),
      CategorySwatch(
        'slate',
        stripe: Color(0xFF6B7A90),
        text: Color(0xFF4A5568),
      ),
      CategorySwatch(
        'plum',
        stripe: Color(0xFF8A3F7A),
        text: Color(0xFF8A3F7A),
      ),
      CategorySwatch(
        'bronze',
        stripe: Color(0xFF6E5B3E),
        text: Color(0xFF6E5B3E),
      ),
    ],
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

  /// Good: online, money up, count matched, saved.
  final Color green;
  final Color greenTint;

  /// Soft warning background.
  final Color butterTint;

  /// Room category colours, in palette order (gold, violet, teal, slate,
  /// plum, bronze).
  final List<CategorySwatch> categories;

  /// The swatch for a category's colour key; an unknown key is slate.
  CategorySwatch category(String key) => categories.firstWhere(
    (s) => s.key == key,
    orElse: () => categories.firstWhere((s) => s.key == 'slate'),
  );

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

/// One room category colour: a 4 px stripe on the room card and the
/// category label's text colour. Category is never shown by colour alone:
/// the label always stays.
@immutable
class CategorySwatch {
  const CategorySwatch(this.key, {required this.stripe, required this.text});

  /// The palette key stored on `bed_categories.colour` (PR 4).
  final String key;
  final Color stripe;
  final Color text;
}
