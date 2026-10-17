/// Guests (FD-3): models and rules. Pure Dart.
library;

import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/id_number.dart';
import '../../../core/contacts/phone.dart';

/// As stored in `guests.id_type`.
enum IdType {
  nationalId('national_id', 'National ID'),
  passport('passport', 'Passport'),
  alienId('alien_id', 'Alien ID');

  const IdType(this.code, this.label);
  final String code;
  final String label;

  static IdType parse(String code) => values.firstWhere((t) => t.code == code);
}

final class Guest {
  const Guest({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.idType,
    required this.idNumber,
    required this.registeredAt,
  });

  final String id;
  final String fullName;

  /// `0722418905` or `+256712345678`.
  final String phone;
  final IdType? idType;
  final String? idNumber;

  /// UTC.
  final DateTime registeredAt;

  /// `National ID ••••3921`, or null without an ID.
  String? get maskedId => switch ((idType, idNumber)) {
    (final IdType type, final String number) =>
      '${type.label} ${maskIdNumber(number)}',
    _ => null,
  };
}

/// A guest's earlier check-ins (both beds of one check-in count once).
final class GuestHistory {
  const GuestHistory({required this.stays, required this.lastCheckIn});

  final int stays;

  /// UTC; null with no stays.
  final DateTime? lastCheckIn;

  /// `3 earlier stays · last on Fri 2 Oct`, for the returning guest's card.
  String get summary => switch ((stays, lastCheckIn)) {
    (0, _) || (_, null) => 'No earlier stays',
    (1, final DateTime last) =>
      '1 earlier stay · last on ${formatDayDate(last)}',
    (final n, final DateTime last) =>
      '$n earlier stays · last on ${formatDayDate(last)}',
  };
}

const _maxName = 80;
final _spaces = RegExp(r'\s+');
final _nationalId = RegExp(r'^\d{6,9}$');
final _document = RegExp(r'^[A-Z0-9]{6,12}$');

/// ID numbers are stored without spaces, in capitals.
String normalizeIdNumber(String input) =>
    input.replaceAll(_spaces, '').toUpperCase();

enum GuestField { fullName, phone, idType, idNumber }

/// The register and correct-details form.
final class GuestForm {
  const GuestForm({
    required this.fullName,
    required this.phone,
    required this.idType,
    required this.idNumber,
  });

  final String fullName;
  final String phone;
  final IdType? idType;
  final String idNumber;

  /// What gets stored: name trimmed with single spaces, the phone's stored
  /// form, the ID normalized. A type with no number is no ID. Call
  /// [validateGuest] first.
  GuestForm normalized() {
    final number = normalizeIdNumber(idNumber);
    return GuestForm(
      fullName: fullName.trim().replaceAll(_spaces, ' '),
      phone: normalizeGuestPhone(phone) ?? phone.trim(),
      idType: number.isEmpty ? null : idType,
      idNumber: number,
    );
  }
}

/// Errors per field; empty if the guest can be saved. Uniqueness of the ID
/// (type + number) is checked by the repository and the database.
Map<GuestField, String> validateGuest(GuestForm input) {
  final name = input.fullName.trim();
  final number = normalizeIdNumber(input.idNumber);
  return {
    if (name.isEmpty)
      GuestField.fullName: 'Enter the full name.'
    else if (name.length > _maxName)
      GuestField.fullName: 'Use at most $_maxName characters.',
    GuestField.phone: ?guestPhoneError(input.phone),
    if (number.isNotEmpty)
      ...switch (input.idType) {
        null => {GuestField.idType: 'Choose the ID type.'},
        IdType.nationalId when !_nationalId.hasMatch(number) => {
          GuestField.idNumber: 'A National ID is 6–9 digits.',
        },
        IdType.passport when !_document.hasMatch(number) => {
          GuestField.idNumber: 'A passport number is 6–12 letters and digits.',
        },
        IdType.alienId when !_document.hasMatch(number) => {
          GuestField.idNumber: 'An Alien ID is 6–12 letters and digits.',
        },
        _ => const <GuestField, String>{},
      },
  };
}

/// What a search box entry looks for, as the receptionist types: a phone
/// prefix in its stored form and an ID prefix, each from 3 characters.
/// Digits alone could be either, so both are searched. Names aren't: an ID
/// prefix needs a digit.
final class GuestQuery {
  const GuestQuery({this.phonePrefix, this.idPrefix});

  factory GuestQuery.parse(String text) {
    var phone = text.replaceAll(RegExp(r'[\s-]'), '');
    if (phone.startsWith('+254')) {
      phone = '0${phone.substring(4)}';
    } else if (phone.startsWith('254')) {
      phone = '0${phone.substring(3)}';
    }
    final phoneOk =
        RegExp(r'^\+?\d+$').hasMatch(phone) &&
        phone.replaceAll('+', '').length >= _minQuery;
    final id = normalizeIdNumber(text);
    // Every ID has digits, so a name typed here isn't searched as one.
    final idOk =
        RegExp(r'^[A-Z0-9]+$').hasMatch(id) &&
        id.contains(RegExp(r'\d')) &&
        id.length >= _minQuery;
    return GuestQuery(
      phonePrefix: phoneOk ? phone : null,
      idPrefix: idOk ? id : null,
    );
  }

  static const _minQuery = 3;

  final String? phonePrefix;
  final String? idPrefix;

  bool get isEmpty => phonePrefix == null && idPrefix == null;
}
