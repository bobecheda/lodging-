import 'package:flutter/painting.dart';

import 'lodging_colors.dart';
import 'lodging_type.dart';

/// Where the wordmark appears, which sets its size: the lodging name's
/// font size in logical pixels.
enum WordmarkSize {
  /// The marine top bar of the shift screen (68 high).
  bar(24),

  /// The desk sidebar (232 wide).
  sidebar(30),

  /// The brand panel of sign in, lock, change password and first-run setup.
  panel(56);

  const WordmarkSize(this.nameSize);
  final double nameSize;
}

/// The wordmark's two lines (docs/design.md, "Brand"): the lodging name in
/// Pirata One with a gold offset shadow about 6% of its size, down-right;
/// "Lodging" under it in IM Fell English SC, letter-spaced 0.3em.
final class WordmarkStyle {
  factory WordmarkStyle.of(
    LodgingColors c,
    WordmarkSize size, {
    required bool onDark,
  }) {
    final s = size.nameSize;
    final ink = onDark ? c.brandCream : c.marine;
    final shift = s * 0.06;
    final wordSize = s * 0.36;
    return WordmarkStyle._(
      name: TextStyle(
        fontFamily: pirataOne,
        fontSize: s,
        height: 1.05,
        color: ink,
        shadows: [
          Shadow(
            color: onDark ? c.brandGoldOnDark : c.brandGoldOnLight,
            offset: Offset(shift, shift),
          ),
        ],
      ),
      word: TextStyle(
        fontFamily: imFellEnglishSc,
        fontSize: wordSize,
        height: 1.2,
        letterSpacing: wordSize * 0.3,
        color: ink,
      ),
      gap: s * 0.12,
    );
  }

  const WordmarkStyle._({
    required this.name,
    required this.word,
    required this.gap,
  });

  /// The lodging name.
  final TextStyle name;

  /// "Lodging".
  final TextStyle word;

  /// Between the two lines.
  final double gap;
}
