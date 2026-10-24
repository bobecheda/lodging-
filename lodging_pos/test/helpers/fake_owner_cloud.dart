import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/contacts/phone.dart';
import 'package:lodging_pos/features/owner_app/data/owner_cloud.dart';

import 'fake_cloud.dart';
import 'fixtures.dart';

export 'fake_cloud.dart' show testOwnerEmail;

/// Columns the owner's phone must never download: guests' full phones and
/// ID numbers, the M-Pesa payout phone, and password hashes.
const forbiddenOwnerColumns = {
  'phone',
  'id_number',
  'id_type',
  'payout_phone',
  'password_hash',
};

/// The cloud as the owner's phone sees it, in memory. Like the privacy
/// rule, it refuses `*`, an empty column list, any column in
/// [forbiddenOwnerColumns] and the `guests` table (the phone reads
/// `owner_guests`, which it computes here from [guests]).
class FakeOwnerCloud implements OwnerCloud {
  FakeOwnerCloud({required this.serverNow});

  /// The cloud as a desk filled it (the rows [desk] holds after a push),
  /// read by the owner, signed in.
  factory FakeOwnerCloud.fromDesk(
    FakeCloud desk, {
    required DateTime Function() serverNow,
  }) {
    final cloud = FakeOwnerCloud(serverNow: serverNow)..stored = owner;
    for (final MapEntry(:key, :value) in desk.tables.entries) {
      if (key == 'guests') {
        cloud.guests.addAll([for (final r in value.values) Map.of(r)]);
      } else {
        cloud.tables[key] = [for (final r in value.values) Map.of(r)];
      }
    }
    cloud._session = owner;
    return cloud;
  }

  /// The cloud's clock, for `server_time`.
  DateTime Function() serverNow;

  /// Tables by name, rows as the cloud returns them (timestamps as ISO
  /// strings).
  final tables = <String, List<Map<String, Object?>>>{};

  /// Guests with their full phones, as the cloud keeps them.
  final guests = <Map<String, Object?>>[];

  /// The phone can't reach the cloud.
  var offline = false;

  OwnerSignIn? _session;

  /// The sign-in kept on the phone from an earlier run.
  OwnerSignIn? stored;

  /// Every table read, in order.
  final reads = <String>[];

  /// Every RPC call, in order: (name, params).
  final calls = <(String, Map<String, Object?>)>[];

  static const owner = OwnerSignIn(userId: 'u-owner', email: testOwnerEmail);

  /// Where each category's price was last edited: (device id, time). A
  /// device starting `dev-` is a desk.
  final priceEdits = <String, (String, String)>{};

  Map<String, Object?>? _row(String table, String id) =>
      this.table(table).where((r) => r['id'] == id).firstOrNull;

  String? _userName(Object? id) =>
      _row('users', '$id')?['full_name'] as String?;

  void _audit(Object? rows) {
    for (final a in (rows as List?) ?? const []) {
      table('audit_log').add(Map.of(a as Map<String, Object?>));
    }
  }

  List<Map<String, Object?>> table(String name) =>
      tables.putIfAbsent(name, () => []);

  void _online() {
    if (offline) throw const OwnerCloudOffline('no network');
  }

  void _signedIn() {
    if (_session == null) throw const OwnerSignInRefused('Sign in again.');
  }

  @override
  Future<OwnerSignIn?> restore() async => _session = stored;

  @override
  Future<OwnerSignIn> signIn({
    required String email,
    required String password,
  }) async {
    _online();
    if (email.trim() != testOwnerEmail || password != testOwner.password) {
      throw const OwnerSignInRefused('Wrong email or password.');
    }
    return _session = stored = owner;
  }

  @override
  Future<void> signOut() async => _session = stored = null;

  @override
  Future<List<Map<String, Object?>>> rows(
    String table,
    List<String> columns, {
    List<Where> where = const [],
    String? orderBy,
  }) async {
    if (columns.isEmpty || columns.contains('*')) {
      fail('The phone read $table without naming its columns.');
    }
    final forbidden = columns.toSet().intersection(forbiddenOwnerColumns);
    if (forbidden.isNotEmpty) fail('The phone read $forbidden from $table.');
    if (table == 'guests') fail('The phone read guests; use owner_guests.');
    _online();
    _signedIn();
    reads.add(table);
    final source = table == 'owner_guests'
        ? [
            for (final g in guests)
              {
                'id': g['id'],
                'full_name': g['full_name'],
                'phone_masked': maskPhone(g['phone']! as String),
              },
          ]
        : this.table(table);
    final out = [
      for (final row in source)
        if (where.every((w) => _matches(row, w)))
          {
            for (final c in columns)
              c: row.containsKey(c)
                  ? row[c]
                  : fail('$table has no column $c in the fake.'),
          },
    ];
    if (orderBy != null) {
      out.sort((a, b) => '${a[orderBy]}'.compareTo('${b[orderBy]}'));
    }
    return out;
  }

  static bool _matches(Map<String, Object?> row, Where w) {
    final v = row[w.column];
    return switch (w) {
      Eq(:final value) => v == value,
      Gte(:final value) =>
        v != null &&
            (v is String
                ? DateTime.parse(v).compareTo(DateTime.parse('$value')) >= 0
                : (v as num) >= (value as num)),
      IsNull() => v == null,
      InList(:final values) => values.contains(v),
    };
  }

  @override
  Future<Object?> rpc(String name, Map<String, Object?> params) async {
    _online();
    _signedIn();
    calls.add((name, params));
    switch (name) {
      case 'server_time':
        return serverNow().toUtc().toIso8601String();
      case 'decide_refund':
        final refundId = params['p_refund_id']! as String;
        final decisions = table('refund_decisions');
        for (final d in decisions) {
          if (d['refund_id'] != refundId) continue;
          if (d['id'] == params['p_id']) return {'status': 'decided'};
          return {
            'status': 'already_decided',
            'decision': d['decision'],
            'decided_at': d['decided_at'],
            'decided_by_name': [
              for (final u in table('users'))
                if (u['id'] == d['decided_by']) u['full_name'],
            ].firstOrNull,
          };
        }
        if (!table('refunds').any((r) => r['id'] == refundId)) {
          return {'status': 'missing'};
        }
        decisions.add({
          'id': params['p_id'],
          'refund_id': refundId,
          'decision': params['p_decision'],
          'note': params['p_note'],
          'decided_by': owner.userId,
          'decided_at': params['p_at'],
          'device_id': params['p_device_id'],
        });
        _audit(params['p_audit']);
        return {'status': 'decided'};
      case 'decide_price_request':
        final requestId = params['p_request_id']! as String;
        final decisions = table('price_decisions');
        for (final d in decisions) {
          if (d['request_id'] != requestId) continue;
          if (d['id'] == params['p_id']) return {'status': 'decided'};
          return {
            'status': 'already_decided',
            'decision': d['decision'],
            'decided_at': d['decided_at'],
            'decided_by_name': _userName(d['decided_by']),
          };
        }
        final request = _row('price_requests', requestId);
        if (request == null) return {'status': 'missing'};
        if (request['withdrawn_at'] != null) return {'status': 'withdrawn'};
        final category = _row(
          'bed_categories',
          request['category_id']! as String,
        )!;
        final approve = params['p_decision'] == 'approved';
        if (approve && category['price_per_night'] != request['old_price']) {
          return {
            'status': 'stale',
            'current_price': category['price_per_night'],
          };
        }
        decisions.add({
          'id': params['p_id'],
          'request_id': requestId,
          'decision': params['p_decision'],
          'note': params['p_note'],
          'decided_by': owner.userId,
          'decided_at': params['p_at'],
          'device_id': params['p_device_id'],
        });
        if (approve) {
          category
            ..['price_per_night'] = request['new_price']
            ..['price_updated_at'] = params['p_at'];
        }
        _audit(params['p_audit']);
        return {'status': 'decided'};
      case 'change_prices':
        final changes = [
          for (final c in params['p_changes']! as List)
            (c as Map).cast<String, Object?>(),
        ];
        for (final c in changes) {
          final category = _row('bed_categories', c['category_id']! as String);
          if (category == null) {
            return {'status': 'missing', 'category_id': c['category_id']};
          }
          if (category['price_per_night'] != c['expected']) {
            final (device, at) =
                priceEdits[category['id']] ??
                ('', category['price_updated_at']! as String);
            return {
              'status': 'stale',
              'category_id': category['id'],
              'current_price': category['price_per_night'],
              'changed_at': at,
              'changed_on': device.isEmpty
                  ? null
                  : device.startsWith('dev-')
                  ? 'desk'
                  : 'phone',
            };
          }
        }
        for (final c in changes) {
          _row('bed_categories', c['category_id']! as String)!
            ..['price_per_night'] = c['price']
            ..['price_updated_at'] = params['p_at'];
          priceEdits[c['category_id']! as String] = (
            params['p_device_id']! as String,
            params['p_at']! as String,
          );
        }
        _audit(params['p_audit']);
        return {'status': 'changed'};
    }
    fail('No fake for $name.');
  }

  /// The owner changes a price at the desk first (not yet seen here).
  void setPriceAtDesk(String categoryId, int price, DateTime at) {
    _row('bed_categories', categoryId)!
      ..['price_per_night'] = price
      ..['price_updated_at'] = at.toIso8601String();
    priceEdits[categoryId] = ('dev-1', at.toIso8601String());
  }

  @override
  Future<String> deviceId() async => 'phone-install-1';

  // ── Data ────────────────────────────────────────────────────────────────

  /// A decision someone else made first (the desk).
  void decideElsewhere(String refundId, {required DateTime at}) =>
      table('refund_decisions').add({
        'id': 'rd-desk',
        'refund_id': refundId,
        'decision': 'approved',
        'note': null,
        'decided_by': 'u-owner',
        'decided_at': at.toIso8601String(),
        'device_id': 'dev-1',
      });
}

/// What the owner's phone tests start from, at [now] (Nairobi 09:30 on a
/// Saturday): the owner and two staff, Deluxe, room 5 with beds A and B, a
/// guest who left early with a refund to decide, a price request, a shift
/// closed KES 300 short, a voided payment, and the desk heard from 2
/// minutes ago with 3 changes waiting.
void seedOwnerLodging(FakeOwnerCloud cloud, DateTime now) {
  String at(Duration ago) => now.subtract(ago).toIso8601String();
  cloud.tables.addAll({
    'users': [
      {'id': 'u-owner', 'full_name': 'Amina Owner', 'role': 'owner'},
      {'id': 'u-sup', 'full_name': 'Grace Akinyi', 'role': 'supervisor'},
      {'id': 'u-desk', 'full_name': 'John Otieno', 'role': 'receptionist'},
    ],
    'settings': [
      {'key': 'lodging_name', 'value': 'UB40'},
      {'key': 'grace_minutes', 'value': '30'},
    ],
    'desk_status': [
      {
        'device_id': 'dev-1',
        'reported_at': at(const Duration(minutes: 2)),
        'last_push_at': at(const Duration(minutes: 3)),
        'pending': 3,
        'problem': null,
      },
    ],
    'bed_categories': [
      {
        'id': 'c-1',
        'name': 'Deluxe',
        'price_per_night': 700,
        'sort_order': 1,
        'is_active': true,
        'price_updated_at': at(const Duration(days: 30)),
      },
      {
        'id': 'c-2',
        'name': 'VIP',
        'price_per_night': 1000,
        'sort_order': 0,
        'is_active': true,
        'price_updated_at': at(const Duration(days: 30)),
      },
      {
        'id': 'c-3',
        'name': 'Normal',
        'price_per_night': 500,
        'sort_order': 3,
        'is_active': false,
        'price_updated_at': at(const Duration(days: 30)),
      },
    ],
    'rooms': [
      {'id': 'r-5', 'room_number': '5', 'is_active': true},
    ],
    'beds': [
      for (final (id, label, clean) in [
        ('b-5a', 'A', 'clean'),
        ('b-5b', 'B', 'not_cleaned'),
      ])
        {
          'id': id,
          'room_id': 'r-5',
          'label': label,
          'category_id': 'c-1',
          'cleanliness': clean,
          'is_active': true,
        },
    ],
    'stays': [
      {
        'id': 'st-1',
        'guest_id': 'g-1',
        'bed_id': 'b-5b',
        'room_number': '5',
        'bed_label': 'B',
        'status': 'closed',
        'check_in_at': at(const Duration(days: 1, hours: 15)),
        'checked_out_at': at(const Duration(hours: 1)),
        'paid_until': at(const Duration(days: -2, hours: -1)),
      },
      {
        'id': 'st-2',
        'guest_id': 'g-2',
        'bed_id': 'b-5a',
        'room_number': '5',
        'bed_label': 'A',
        'status': 'active',
        'check_in_at': at(const Duration(hours: 20)),
        'checked_out_at': null,
        'paid_until': at(const Duration(hours: -24, minutes: -30)),
      },
    ],
    'payments': [
      {
        'id': 'p-1',
        'receipt_number': 'R-000041',
        'received_at': at(const Duration(days: 1, hours: 15)),
        'amount': 2800,
        'method': 'cash',
      },
      {
        'id': 'p-2',
        'receipt_number': 'R-000042',
        'received_at': at(const Duration(hours: 2)),
        'amount': 1400,
        'method': 'paybill',
      },
      {
        'id': 'p-3',
        'receipt_number': 'R-000043',
        'received_at': at(const Duration(hours: 1)),
        'amount': 700,
        'method': 'cash',
      },
    ],
    'stay_charges': [
      {
        'stay_id': 'st-1',
        'payment_id': 'p-1',
        'nights': 4,
        'price_per_night': 700,
        'category_name': 'Deluxe',
        'period_start': at(const Duration(days: 1, hours: 23, minutes: 30)),
        'period_end': at(const Duration(days: -2, hours: -1)),
      },
      {
        'stay_id': 'st-2',
        'payment_id': 'p-2',
        'nights': 2,
        'price_per_night': 700,
        'category_name': 'Deluxe',
        'period_start': at(const Duration(hours: 23, minutes: 30)),
        'period_end': at(const Duration(hours: -24, minutes: -30)),
      },
    ],
    'refunds': [
      {
        'id': 'rf-1',
        'stay_id': 'st-1',
        'nights': 2,
        'price_per_night': 700,
        'amount': 1400,
        'requested_by': 'u-desk',
        'requested_at': at(const Duration(hours: 1)),
        'method': null,
        'mpesa_code': null,
        'shift_id': null,
        'paid_by': null,
        'paid_at': null,
        'receipt_number': null,
      },
    ],
    'refund_decisions': [],
    'price_requests': [
      {
        'id': 'pr-1',
        'category_id': 'c-1',
        'old_price': 700,
        'new_price': 750,
        'reason': 'Other lodgings nearby charge 800.',
        'requested_by': 'u-sup',
        'requested_at': at(const Duration(minutes: 15)),
        'withdrawn_at': null,
      },
    ],
    'price_decisions': [],
    'shifts': [
      {
        'id': 's-1',
        'user_id': 'u-desk',
        'status': 'closed',
        'closed_at': at(const Duration(hours: 3)),
        'variance': -300,
      },
      {
        'id': 's-2',
        'user_id': 'u-desk',
        'status': 'closed',
        'closed_at': at(const Duration(days: 1)),
        'variance': 0,
      },
    ],
    'voids': [
      {
        'id': 'v-1',
        'target_type': 'payment',
        'target_id': 'p-3',
        'reason': 'Wrong bed',
        'voided_by': 'u-sup',
        'voided_at': at(const Duration(minutes: 30)),
      },
    ],
  });
  cloud.guests.addAll([
    {
      'id': 'g-1',
      'full_name': 'Peter Kamau',
      'phone': '0711000482',
      'id_number': '12343921',
    },
    {'id': 'g-2', 'full_name': 'Jane Okello', 'phone': '+256712345678'},
  ]);
}
