/// A bed category and its current price per block (whole KES).
class BedCategory {
  const BedCategory({
    required this.id,
    required this.name,
    required this.pricePerBlock,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String name;
  final int pricePerBlock;
  final int sortOrder;
  final bool isActive;
}
