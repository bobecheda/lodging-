import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lodging_pos/features/owner_app/domain/owner_more.dart';

import '../helpers/fake_owner_cloud.dart' show forbiddenOwnerColumns;

/// The owner's phone app (`lib/main_owner.dart`, `features/owner_app`):
///
/// - it never downloads a guest's ID number or full phone (nor the M-Pesa
///   payout phone, nor password hashes): its queries name their columns,
///   never `*`, and read guests only through the masked `owner_guests`;
/// - it runs on the web and keeps nothing guest-related on the phone, so it
///   never reaches the desk's database, sync, files or settings.
///
/// `FakeOwnerCloud` refuses the same columns at run time.
void main() {
  List<File> ownerSources() => [
    File('lib/main_owner.dart'),
    for (final f in Directory(
      'lib/features/owner_app',
    ).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        f,
  ];

  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('no query names a forbidden column, `*` or the guests table', () {
    final literal = RegExp(r"""'([^'\\]*)'""");
    final problems = <String>[];
    for (final f in ownerSources()) {
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final s = m.group(1)!;
        if (forbiddenOwnerColumns.contains(s) ||
            s == '*' ||
            s == 'guests' ||
            s.split(',').any((c) => forbiddenOwnerColumns.contains(c.trim()))) {
          problems.add('${rel(f)}: \'$s\'');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('every read names its columns', () {
    // `rows('table', [ ... ])`, or a named constant list.
    final reads = RegExp(r"\.rows\(\s*'(\w+)',\s*(\[|\w)");
    var count = 0;
    for (final f in ownerSources()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\.rows\(').allMatches(src)) {
        final at = src.substring(m.start, (m.start + 200).clamp(0, src.length));
        if (at.startsWith('.rows(\n    String table')) continue; // the API
        expect(
          reads.hasMatch(at),
          isTrue,
          reason: '${rel(f)}: ${at.split('\n').take(3).join(' ')}',
        );
        count++;
      }
    }
    expect(count, greaterThan(10));
  });

  test('audit details are read only for the agreed entities, never a '
      'refund’s row (it carries payout_phone)', () {
    expect(auditDetailEntities, {
      'bed_categories',
      'refund_decisions',
      'price_decisions',
      'voids',
      'shifts',
    });
    final details = RegExp(r"'(before_json|after_json)'");
    var reads = 0;
    for (final f in ownerSources()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\.rows\(').allMatches(src)) {
        final end = src.indexOf(');', m.start);
        final call = src.substring(m.start, end < 0 ? src.length : end);
        if (!details.hasMatch(call)) continue;
        reads++;
        expect(
          call,
          contains("InList('entity', auditDetailEntities"),
          reason: '${rel(f)} reads audit details without the allowlist',
        );
        expect(call, contains("'audit_log'"));
      }
    }
    expect(reads, greaterThan(0));
    // payout_phone is never named (the first test), and FakeOwnerCloud
    // refuses it at run time.
    expect(forbiddenOwnerColumns, contains('payout_phone'));
  });

  test('the phone app imports nothing of the desk\'s database, sync, files '
      'or settings', () {
    const banned = [
      'package:drift',
      'package:drift_flutter',
      'package:sqlite3',
      'package:path_provider',
      'package:printing',
      'dart:io',
      'lib/core/database/',
      'lib/core/sync/',
      'lib/core/audit/',
      'lib/core/settings/settings_repository.dart',
    ];
    final seen = <String>{};
    final problems = <String>[];
    final import = RegExp(
      r"^\s*(?:import|export)\s+'([^']+)'",
      multiLine: true,
    );
    void walk(String path) {
      if (!seen.add(path)) return;
      final src = File(path).readAsStringSync();
      for (final m in import.allMatches(src)) {
        final uri = m.group(1)!;
        String? next;
        if (uri.startsWith('package:lodging_pos/')) {
          next = 'lib/${uri.substring('package:lodging_pos/'.length)}';
        } else if (!uri.contains(':')) {
          next = File(path).parent.uri.resolve(uri).toFilePath(windows: false);
          next = next.substring(next.indexOf('lib/'));
        }
        final shown = next ?? uri;
        if (banned.any(shown.startsWith)) problems.add('$path → $shown');
        if (next != null) walk(next);
      }
    }

    walk('lib/main_owner.dart');
    expect(problems, isEmpty);
    expect(
      seen,
      contains('lib/features/owner_app/presentation/owner_app.dart'),
    );
  });
}
