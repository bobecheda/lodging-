/// Money is whole KES as `int` (see CLAUDE.md). Display: `KES 1,000`.
String formatKes(int amount) {
  final digits = amount.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return 'KES ${amount < 0 ? '-' : ''}$grouped';
}

final _kesInput = RegExp(
  r'^(?:kes\s*)?(\d{1,3}(?:,\d{3})+|\d+)$',
  caseSensitive: false,
);

/// Parses a whole, non-negative KES amount typed by a user: `1000`,
/// `1,000` or `KES 1,000`. Returns null for anything else.
int? parseKes(String input) {
  final match = _kesInput.firstMatch(input.trim());
  if (match == null) return null;
  return int.tryParse(match.group(1)!.replaceAll(',', ''));
}
