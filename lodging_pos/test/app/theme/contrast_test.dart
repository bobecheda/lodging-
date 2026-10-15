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
    'white on red (overstay tile, Renew)': (c.white, c.red),
  };

  for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
    test('$name ≥ 4.5:1', () {
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
    });
  }
}
