/// Kenyan phone numbers: one rule for housekeepers (AD-4) and guests (FD-3),
/// and one way to mask them in lists and audit entries (Data Protection Act;
/// design.md, "Mask personal data in lists").
library;

final _separators = RegExp(r'[\s-]');
final _stored = RegExp(r'^0[17]\d{8}$');

/// The stored 10-digit form (`0722123310`), or null if [input] isn't a
/// Kenyan 07… or 01… number. Spaces and dashes are ignored; `+254` and `254`
/// become `0`.
String? normalizePhone(String input) {
  var digits = input.replaceAll(_separators, '');
  if (digits.startsWith('+254')) {
    digits = '0${digits.substring(4)}';
  } else if (digits.startsWith('254') && digits.length == 12) {
    digits = '0${digits.substring(3)}';
  }
  return _stored.hasMatch(digits) ? digits : null;
}

/// Null if [input] can be stored. Blank is fine unless [required].
String? phoneError(String input, {bool required = false}) {
  if (input.trim().isEmpty) {
    return required ? 'Enter a phone number.' : null;
  }
  return normalizePhone(input) == null
      ? 'Enter a Kenyan number starting 07 or 01, e.g. 0722 123 310.'
      : null;
}

/// `0722 ••• 310` for lists; [compact] `0722•••310` for audit entries, so a
/// change still shows without keeping the number.
String maskPhone(String phone, {bool compact = false}) {
  if (phone.length < 8) return '•••';
  final gap = compact ? '' : ' ';
  return '${phone.substring(0, 4)}$gap•••$gap'
      '${phone.substring(phone.length - 3)}';
}
