/// A bed category and its current price per night (whole KES).
class BedCategory {
  const BedCategory({
    required this.id,
    required this.name,
    required this.pricePerNight,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String name;
  final int pricePerNight;
  final int sortOrder;
  final bool isActive;
}
