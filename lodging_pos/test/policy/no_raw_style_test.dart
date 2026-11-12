import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Raw colours, font sizes and font families live only in lib/app/theme/.
/// Everything else reads LodgingColors / LodgingType from the theme.
void main() {
  test('no raw colours or font sizes outside lib/app/theme/', () {
    final banned = <RegExp, String>{
      RegExp(r'\bColor\s*\(\s*0x'): 'raw hex colour',
      RegExp(r'\bColor\.from(ARGB|RGBO)\b'): 'raw colour',
      RegExp(r'\bColors\.(?!transparent\b)'): 'Material Colors palette',
      RegExp(r'\bfontSize\s*:'): 'font size',
      RegExp(r'\bfontFamily\s*:'): 'font family',
    };
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where(
          (f) => !f.path.replaceAll(r'\', '/').startsWith('lib/app/theme/'),
        );
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: pattern, value: what) in banned.entries) {
          if (pattern.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}: $what: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  // v2 (docs/design-system.md, "Type"): weights 400, 500 and 600 only.
  // The receipt PDF has its own print styles; the wordmark sets no weight.
  test('no font weight above 600 in the app', () {
    final heavy = RegExp(r'\bFontWeight\.(w700|w800|w900|bold)\b');
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where((f) => !f.path.endsWith('receipt_print_style.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (heavy.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
