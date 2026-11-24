import '../../../core/category_colour_keys.dart';

/// A bed category and its current price per night (whole KES).
class BedCategory {
  const BedCategory({
    required this.id,
    required this.name,
    required this.pricePerNight,
    required this.sortOrder,
    required this.isActive,
    this.colour = defaultCategoryColour,
  });

  final String id;
  final String name;
  final int pricePerNight;
  final int sortOrder;
  final bool isActive;

  /// Its colour key on room cards and charts (v2 PR 4): one of
  /// [categoryColourKeys].
  final String colour;
}
