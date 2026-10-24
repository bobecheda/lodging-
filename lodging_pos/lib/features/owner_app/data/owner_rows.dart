import 'owner_cloud.dart';

/// Reading the cloud's JSON rows.
extension OwnerRow on Map<String, Object?> {
  String str(String column) => this[column]! as String;
  String? strOrNull(String column) => this[column] as String?;
  int integer(String column) => (this[column]! as num).toInt();
  int? intOrNull(String column) => (this[column] as num?)?.toInt();

  /// A `timestamptz`, as UTC.
  DateTime time(String column) => DateTime.parse(str(column)).toUtc();
  DateTime? timeOrNull(String column) {
    final v = strOrNull(column);
    return v == null ? null : DateTime.parse(v).toUtc();
  }
}

/// The columns of `users` the phone reads (never `password_hash`).
const userColumns = ['id', 'full_name', 'role'];

/// Everyone's id → (full name, role).
Future<Map<String, ({String name, String role})>> loadUsers(
  OwnerCloud cloud,
) async => {
  for (final u in await cloud.rows('users', userColumns))
    u.str('id'): (name: u.str('full_name'), role: u.str('role')),
};

/// Guests by id: name and masked phone, from `owner_guests` (the phone
/// never reads `guests`, so it never has a full phone or an ID number).
Future<Map<String, ({String name, String phoneMasked})>> loadGuests(
  OwnerCloud cloud,
  Iterable<String> ids,
) async {
  final wanted = ids.toSet().toList();
  if (wanted.isEmpty) return const {};
  return {
    for (final g in await cloud.rows(
      'owner_guests',
      ['id', 'full_name', 'phone_masked'],
      where: [InList('id', wanted)],
    ))
      g.str('id'): (
        name: g.str('full_name'),
        phoneMasked: g.str('phone_masked'),
      ),
  };
}
