import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift shares one stream between watched queries with the same SQL text,
/// whatever tables each says it reads from. Two "re-run when these tables
/// change" watches written as a bare `customSelect('SELECT 1', ...)` would
/// share one stream, and one of them would miss its own changes (v2 PR 3:
/// the Cash badge hid the Voids panel's refresh). Each such watch gets its
/// own text, e.g. `'SELECT 1 AS watch_void_view'`.
void main() {
  test('every SELECT-1 watch has its own SQL text', () {
    final pattern = RegExp(r"""['"](SELECT 1[^'"]*)['"]""");
    final seen = <String, String>{};
    final problems = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          final sql = m.group(1)!;
          final where = '${file.path}:${i + 1}';
          if (sql == 'SELECT 1') {
            problems.add('$where: a bare SELECT 1; name it');
          } else if (seen[sql] case final other?) {
            problems.add('$where: "$sql" also at $other');
          } else {
            seen[sql] = where;
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
