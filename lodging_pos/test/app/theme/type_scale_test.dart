import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/theme/theme.dart';

/// The v2 type scale (docs/design-system.md, "Type"): three weights
/// (400/500/600), none above 600, nothing below 12.
void main() {
  final t = LodgingType.from(LodgingColors.light);
  final styles = <String, TextStyle>{
    'pageTitle': t.pageTitle,
    'sectionTitle': t.sectionTitle,
    'body': t.body,
    'bodyMedium': t.bodyMedium,
    'secondary': t.secondary,
    'secondaryMedium': t.secondaryMedium,
    'meta': t.meta,
    'moneyHero': t.moneyHero,
    'money': t.money,
    'moneySmall': t.moneySmall,
  };

  test('each style has its v2 size, weight and family', () {
    const spec = <String, (double, FontWeight, String)>{
      'pageTitle': (24, FontWeight.w600, manrope),
      'sectionTitle': (18, FontWeight.w600, manrope),
      'body': (16, FontWeight.w400, manrope),
      'bodyMedium': (16, FontWeight.w500, manrope),
      'secondary': (14, FontWeight.w400, manrope),
      'secondaryMedium': (14, FontWeight.w500, manrope),
      'meta': (12, FontWeight.w500, manrope),
      'moneyHero': (30, FontWeight.w600, plexMono),
      'money': (18, FontWeight.w600, plexMono),
      'moneySmall': (14, FontWeight.w500, plexMono),
    };
    expect(styles.keys, unorderedEquals(spec.keys));
    for (final MapEntry(key: name, value: (size, weight, family))
        in spec.entries) {
      final s = styles[name]!;
      expect(s.fontSize, size, reason: name);
      expect(s.fontWeight, weight, reason: name);
      expect(s.fontFamily, family, reason: name);
    }
  });

  test('three weights at most, none above 600, nothing below 12', () {
    final weights = styles.values.map((s) => s.fontWeight).toSet();
    expect(weights.length, lessThanOrEqualTo(3));
    for (final MapEntry(key: name, value: s) in styles.entries) {
      expect(s.fontWeight!.value, lessThanOrEqualTo(600), reason: name);
      expect(s.fontSize, greaterThanOrEqualTo(12), reason: name);
      expect(s.letterSpacing, isNull, reason: '$name: no caps tracking');
    }
  });

  test('every Manrope weight the scale uses is bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manropeBlock = RegExp(
      r'- family: Manrope\s+fonts:((?:\s+- asset: .+\s+weight: \d+)+)',
    ).firstMatch(pubspec)!.group(1)!;
    final bundled = RegExp(r'asset: (\S+)\s+weight: (\d+)')
        .allMatches(manropeBlock)
        .map((m) => (m.group(1)!, int.parse(m.group(2)!)))
        .toList();
    for (final (asset, _) in bundled) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    final used = styles.values
        .where((s) => s.fontFamily == manrope)
        .map((s) => s.fontWeight!.value)
        .toSet();
    expect(bundled.map((b) => b.$2), containsAll(used));
  });
}
