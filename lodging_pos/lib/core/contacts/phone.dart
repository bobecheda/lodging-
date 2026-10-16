/// Kenyan phone numbers: one rule for housekeepers (AD-4) and guests (FD-3),
/// and one way to mask them in lists and audit entries (Data Protection Act;
/// design.md, "Mask personal data in lists").
library;

final _separators = RegExp(r'[\s-]');
final _stored = RegExp(r'^0[17]\d{8}$');
final _international = RegExp(r'^\+\d{8,15}$');

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

/// Guests (FD-3) may also give an international number. The Kenyan rule
/// comes first, so `+254…` still becomes `07…`/`01…`; otherwise `+` and 8–15
/// digits, stored as `+` and digits only. Null if neither.
String? normalizeGuestPhone(String input) {
  final kenyan = normalizePhone(input);
  if (kenyan != null) return kenyan;
  final compact = input.replaceAll(_separators, '');
  return _international.hasMatch(compact) ? compact : null;
}

/// Null if a guest's [input] can be stored; guests must give a phone.
String? guestPhoneError(String input) {
  if (input.trim().isEmpty) return 'Enter a phone number.';
  return normalizeGuestPhone(input) == null
      ? 'Enter a Kenyan number (07…, 01…) or an international one starting '
            'with +.'
      : null;
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
/// change still shows without keeping the number. International numbers
/// keep their `+`: `+2567 ••• 678`. The first 4 and last 3 digits show.
String maskPhone(String phone, {bool compact = false}) {
  final plus = phone.startsWith('+') ? '+' : '';
  final digits = phone.substring(plus.length);
  if (digits.length < 8) return '•••';
  final gap = compact ? '' : ' ';
  return '$plus${digits.substring(0, 4)}$gap•••$gap'
      '${digits.substring(digits.length - 3)}';
}
