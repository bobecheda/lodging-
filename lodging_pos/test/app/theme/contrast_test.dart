import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/theme/theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const c = LodgingColors.light;

  // Text/background pairs the spec relies on; body text needs 4.5:1.
  final pairs = <String, (Color, Color)>{
    'ink on white': (c.ink, c.white),
    'ink on surface': (c.ink, c.surface),
    'inkSoft on white': (c.inkSoft, c.white),
    'muted on white': (c.muted, c.white),
    'muted on surface': (c.muted, c.surface),
    'white on marine (buttons, occupied tiles)': (c.white, c.marine),
    'navText on marine': (c.navText, c.marine),
    'navMuted on marine': (c.navMuted, c.marine),
    'marine on white (links, READY)': (c.marine, c.white),
    'marine on marineTint (info notes, chips)': (c.marine, c.marineTint),
    'marine on marineTintStrong (selected option)': (
      c.marine,
      c.marineTintStrong,
    ),
    'butterText on butter (needs cleaning, warnings)': (c.butterText, c.butter),
    'redText on redTint (alerts)': (c.redText, c.redTint),
    'redText on white (destructive outline)': (c.redText, c.white),
    'redDark on white (overstay pill text)': (c.redDark, c.white),
    'white on red (overstay tile, Extend)': (c.white, c.red),
    'green on white (online, money up)': (c.green, c.white),
    'green on greenTint (good notes)': (c.green, c.greenTint),
    'butterText on butterTint (soft warnings)': (c.butterText, c.butterTint),
    for (final s in c.categories)
      'category ${s.key} label on white': (s.text, c.white),
  };

  for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
    test('$name ≥ 4.5:1', () {
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
    });
  }

  // A category stripe isn't text: 3:1 against the white card (WCAG 1.4.11).
  for (final s in c.categories) {
    test('category ${s.key} stripe on white ≥ 3:1', () {
      expect(contrast(s.stripe, c.white), greaterThanOrEqualTo(3));
    });
  }

  test('the category palette, in order (docs/design-system.md)', () {
    expect(
      [for (final s in c.categories) (s.key, s.stripe, s.text)],
      const [
        ('gold', Color(0xFFB8862B), Color(0xFF7A5A12)),
        ('violet', Color(0xFF5B4B9A), Color(0xFF5B4B9A)),
        ('teal', Color(0xFF1F7A86), Color(0xFF1F7A86)),
        ('slate', Color(0xFF6B7A90), Color(0xFF4A5568)),
        ('plum', Color(0xFF8A3F7A), Color(0xFF8A3F7A)),
        ('bronze', Color(0xFF6E5B3E), Color(0xFF6E5B3E)),
      ],
    );
    expect(c.category('violet').key, 'violet');
    expect(c.category('unknown').key, 'slate', reason: 'falls back to slate');
  });
}
