import '../category_colour_keys.dart';
import 'seed.dart';

export '../category_colour_keys.dart';

/// The seeded categories' colours (docs/ui-redesign-brief.md): VIP gold,
/// Deluxe violet, Comfort teal, Normal slate. The v12 migration fills them
/// in by id, the cloud's migration (`20261124000000_category_colours.sql`)
/// the same way; any other category is [defaultCategoryColour].
const seedCategoryColours = {
  SeedIds.vip: 'gold',
  SeedIds.deluxe: 'violet',
  SeedIds.comfort: 'teal',
  SeedIds.normal: 'slate',
};
