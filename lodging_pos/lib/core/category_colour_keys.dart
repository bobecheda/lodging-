/// Room category colour keys (v2 PR 4, `bed_categories.colour`), in the
/// order new categories take them. Pure Dart with no imports, so the
/// owner's phone may use it too. The colours themselves live in the theme
/// (`LodgingColors.categories`) and the seeded categories' colours in
/// `core/database/category_colours.dart`;
/// `test/core/database/category_colours_test.dart` keeps them all equal.
const categoryColourKeys = [
  'gold',
  'violet',
  'teal',
  'slate',
  'plum',
  'bronze',
];

/// The colour of a category nobody chose one for.
const defaultCategoryColour = 'slate';

/// A new category's colour: the first key no category has yet, in palette
/// order, or [defaultCategoryColour] once all six are taken.
String nextCategoryColour(Iterable<String> used) {
  final taken = used.toSet();
  return categoryColourKeys.firstWhere(
    (k) => !taken.contains(k),
    orElse: () => defaultCategoryColour,
  );
}

/// "Gold", "Violet": a key as people read it.
String categoryColourLabel(String key) =>
    key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
