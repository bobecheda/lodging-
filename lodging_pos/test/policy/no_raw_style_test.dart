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
}
