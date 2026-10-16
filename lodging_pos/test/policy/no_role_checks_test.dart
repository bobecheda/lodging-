import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BR-13: access is checked by action through the permission map
/// (`lib/core/auth/permissions.dart`), never by comparing roles, so a new
/// role (e.g. supervisor) only needs an edit to the map.
void main() {
  test('no role comparisons outside the permission map', () {
    final banned = <RegExp, String>{
      RegExp(r'[=!]=\s*Role\.'): 'role comparison',
      RegExp(r'Role\.\w+\s*[=!]='): 'role comparison',
      RegExp(r'\.role\s*[=!]='): 'role comparison',
      RegExp(r'\brequireAdmin\b'): 'requireAdmin (use requirePermission)',
      RegExp(r'\bAdminOnly\b'): 'AdminOnly (use NotPermitted)',
    };
    const allowed = {'lib/core/auth/permissions.dart'};
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where((f) => !allowed.contains(f.path.replaceAll(r'\', '/')));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: pattern, value: what) in banned.entries) {
          if (pattern.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}: $what: ${lines[i].trim()}');
            break;
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
