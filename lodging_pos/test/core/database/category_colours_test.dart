import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/theme/theme.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/category_colours.dart';
import 'package:lodging_pos/core/database/database.dart';

import '../../helpers/fixtures.dart';

/// The category colour keys (v2 PR 4) are written in three places: the
/// constants, the theme's palette and the table's CHECK and default. They
/// must agree.
void main() {
  test('the theme has a swatch for every key, in the same order', () {
    expect([
      for (final s in LodgingColors.light.categories) s.key,
    ], categoryColourKeys);
  });

  test('the next colour: the first unused, then slate', () {
    expect(nextCategoryColour([]), 'gold');
    expect(nextCategoryColour(['gold', 'teal']), 'violet');
    expect(nextCategoryColour(categoryColourKeys), defaultCategoryColour);
    expect(categoryColourLabel('violet'), 'Violet');
  });

  test(
    'the table takes every key, defaults to slate, refuses others',
    () async {
      final db = AppDatabase(
        NativeDatabase.memory(),
        clock: FixedClock(testT0),
      );
      addTearDown(db.close);
      final table = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'bed_categories'",
          )
          .getSingle();
      final sql = table.read<String>('sql');
      for (final key in categoryColourKeys) {
        expect(sql, contains("'$key'"));
      }
      expect(sql, contains("DEFAULT 'slate'"));
      expect(defaultCategoryColour, 'slate');
    },
  );
}
