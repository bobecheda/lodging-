import '../../../core/settings/setting_defaults.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../payments/domain/payment_rules.dart';
import '../../price_requests/domain/price_request.dart';
import '../../setup/domain/bed_category.dart';
import '../../setup/domain/prices_settings.dart';
import '../../setup/domain/rooms.dart';
import '../domain/owner_today.dart';
import 'owner_cloud.dart';
import 'owner_rows.dart';

/// Reads the owner's Today, Money, Beds and Prices from the cloud: the same
/// figures as the desk's `DashboardRepository`, bed board and Prices,
/// column by column (only what the screens show; no guest columns but the
/// masked names of refunds waiting).
class OwnerTodayRepository {
  OwnerTodayRepository(this._cloud);

  final OwnerCloud _cloud;

  Future<OwnerToday> load(DateTime now) async {
    // Last month's start also covers the same weekday last week.
    final from = monthStart(sameMomentLastMonth(now));
    final since = attentionSince(now);
    final users = await loadUsers(_cloud);
    String name(String id) => users[id]?.name ?? '—';
    final voids = await _cloud.rows('voids', [
      'id',
      'target_type',
      'target_id',
      'reason',
      'voided_by',
      'voided_at',
    ]);
    final voided = {
      for (final v in voids) (v.str('target_type'), v.str('target_id')),
    };
    final settings = {
      for (final s in await _cloud.rows(
        'settings',
        ['key', 'value'],
        where: const [
          InList('key', [SettingKeys.lodgingName, SettingKeys.graceMinutes]),
        ],
      ))
        s.str('key'): s.str('value'),
    };
    final categories = await _categories();
    final (rooms, bedsByCategory) = await _rooms(categories);
    final requests = await _priceRequests(users, categories);
    return OwnerToday(
      lodgingName: settings[SettingKeys.lodgingName] ?? '',
      graceMinutes: graceMinutesFrom(settings[SettingKeys.graceMinutes]),
      desks: await _desks(),
      moves: await _moves(from, voided),
      stays: await _stayNights(from, voided),
      refunds: await _refundsAwaiting(name),
      prices: [
        for (final r in requests)
          PriceAwaiting(
            requestId: r.id,
            categoryName: r.category.name,
            oldPrice: r.request.oldPrice,
            newPrice: r.request.newPrice,
            requestedBy: r.requestedByName,
            requestedByRole: r.requestedByRole,
            requestedAt: r.request.requestedAt,
          ),
      ],
      shortages: shortages(await _closedShifts(since, name), now),
      voids: await _paymentVoids(voids, since, name),
      rooms: rooms,
      categories: [
        for (final c in categories.values)
          OwnerCategory(c, beds: bedsByCategory[c.id] ?? 0),
      ],
      priceRequests: requests,
    );
  }

  Future<List<DeskStatus>> _desks() async => [
    for (final d in await _cloud.rows('desk_status', [
      'device_id',
      'reported_at',
      'last_push_at',
      'pending',
      'problem',
    ]))
      DeskStatus(
        deviceId: d.str('device_id'),
        reportedAt: d.time('reported_at'),
        lastPushAt: d.timeOrNull('last_push_at'),
        pending: d.integer('pending'),
        problem: d.strOrNull('problem'),
      ),
  ];

  /// Payments received and refunds paid out at or after [from].
  Future<List<MoneyMove>> _moves(
    DateTime from,
    Set<(String, String)> voided,
  ) async {
    final at = from.toIso8601String();
    return [
      for (final p in await _cloud.rows(
        'payments',
        ['id', 'received_at', 'amount', 'method'],
        where: [Gte('received_at', at)],
      ))
        MoneyMove(
          at: p.time('received_at'),
          amount: p.integer('amount'),
          method: PaymentMethod.parse(p.str('method')),
          isPayout: false,
          voided: voided.contains(('payment', p.str('id'))),
        ),
      for (final r in await _cloud.rows(
        'refunds',
        ['id', 'paid_at', 'amount', 'method'],
        where: [Gte('paid_at', at)],
      ))
        MoneyMove(
          at: r.time('paid_at'),
          amount: r.integer('amount'),
          method: PaymentMethod.parse(r.str('method')),
          isPayout: true,
          voided: voided.contains(('refund', r.str('id'))),
        ),
    ];
  }

  /// Every stay with a night ending at or after [from], for occupancy.
  Future<List<StayNights>> _stayNights(
    DateTime from,
    Set<(String, String)> voided,
  ) async {
    const columns = [
      'stay_id',
      'nights',
      'period_end',
      'category_name',
      'price_per_night',
    ];
    final recent = await _cloud.rows(
      'stay_charges',
      columns,
      where: [Gte('period_end', from.toIso8601String())],
    );
    final stayIds = {for (final c in recent) c.str('stay_id')}.toList();
    if (stayIds.isEmpty) return const [];
    // All of those stays' charges (an earlier one may end before [from]).
    final all = await _cloud.rows(
      'stay_charges',
      columns,
      where: [InList('stay_id', stayIds)],
    );
    final refunds = await _cloud.rows(
      'refunds',
      ['id', 'stay_id', 'nights'],
      where: [InList('stay_id', stayIds)],
    );
    final rejected = refunds.isEmpty
        ? const <String>{}
        : {
            for (final d in await _cloud.rows(
              'refund_decisions',
              ['refund_id'],
              where: [
                const Eq('decision', 'rejected'),
                InList('refund_id', [for (final r in refunds) r.str('id')]),
              ],
            ))
              d.str('refund_id'),
          };
    final refundedNights = {
      for (final r in refunds)
        if (!rejected.contains(r.str('id')))
          r.str('stay_id'): r.integer('nights'),
    };
    final byStay = <String, List<ChargeNights>>{};
    for (final c in all) {
      byStay
          .putIfAbsent(c.str('stay_id'), () => [])
          .add(
            ChargeNights(
              nights: c.integer('nights'),
              periodEnd: c.time('period_end'),
              categoryName: c.str('category_name'),
              pricePerNight: c.integer('price_per_night'),
            ),
          );
    }
    return [
      for (final MapEntry(key: stayId, value: list) in byStay.entries)
        StayNights(
          charges: list,
          voided: voided.contains(('stay', stayId)),
          refundedNights: refundedNights[stayId] ?? 0,
        ),
    ];
  }

  /// Refunds waiting for the owner's decision (BR-8a), oldest first.
  Future<List<RefundAwaiting>> _refundsAwaiting(
    String Function(String id) name,
  ) async {
    // A paid refund was decided; the rest are checked against decisions.
    final open = await _cloud.rows(
      'refunds',
      ['id', 'stay_id', 'nights', 'amount', 'requested_by', 'requested_at'],
      where: const [IsNull('paid_at')],
      orderBy: 'requested_at',
    );
    if (open.isEmpty) return const [];
    final decided = {
      for (final d in await _cloud.rows(
        'refund_decisions',
        ['refund_id'],
        where: [
          InList('refund_id', [for (final r in open) r.str('id')]),
        ],
      ))
        d.str('refund_id'),
    };
    final waiting = [
      for (final r in open)
        if (!decided.contains(r.str('id'))) r,
    ];
    if (waiting.isEmpty) return const [];
    final stays = {
      for (final s in await _cloud.rows(
        'stays',
        ['id', 'guest_id', 'room_number', 'bed_label'],
        where: [
          InList('id', [for (final r in waiting) r.str('stay_id')]),
        ],
      ))
        s.str('id'): s,
    };
    final guests = await loadGuests(_cloud, [
      for (final s in stays.values) s.str('guest_id'),
    ]);
    return [
      for (final r in waiting)
        if (stays[r.str('stay_id')] case final stay?)
          RefundAwaiting(
            refundId: r.str('id'),
            guestName: guests[stay.str('guest_id')]?.name ?? '—',
            roomNumber: stay.str('room_number'),
            bedLabel: stay.str('bed_label'),
            nights: r.integer('nights'),
            amount: r.integer('amount'),
            requestedBy: name(r.str('requested_by')),
            requestedAt: r.time('requested_at'),
          ),
    ];
  }

  /// Every category, in sort order.
  Future<Map<String, BedCategory>> _categories() async => {
    for (final c in await _cloud.rows('bed_categories', [
      'id',
      'name',
      'price_per_night',
      'sort_order',
      'is_active',
    ], orderBy: 'sort_order'))
      c.str('id'): BedCategory(
        id: c.str('id'),
        name: c.str('name'),
        pricePerNight: c.integer('price_per_night'),
        sortOrder: c.integer('sort_order'),
        isActive: c['is_active']! as bool,
      ),
  };

  /// Price requests waiting for the owner (BR-2): not withdrawn, not
  /// decided; oldest first.
  Future<List<OwnerPriceRequest>> _priceRequests(
    Map<String, ({String name, String role})> users,
    Map<String, BedCategory> categories,
  ) async {
    final open = await _cloud.rows(
      'price_requests',
      [
        'id',
        'category_id',
        'old_price',
        'new_price',
        'reason',
        'requested_by',
        'requested_at',
      ],
      where: const [IsNull('withdrawn_at')],
      orderBy: 'requested_at',
    );
    if (open.isEmpty) return const [];
    final decided = {
      for (final d in await _cloud.rows(
        'price_decisions',
        ['request_id'],
        where: [
          InList('request_id', [for (final r in open) r.str('id')]),
        ],
      ))
        d.str('request_id'),
    };
    return [
      for (final r in open)
        if (!decided.contains(r.str('id')))
          if (categories[r.str('category_id')] case final category?)
            OwnerPriceRequest(
              request: PriceRequest(
                id: r.str('id'),
                categoryId: category.id,
                oldPrice: r.integer('old_price'),
                newPrice: r.integer('new_price'),
                reason: r.strOrNull('reason'),
                requestedBy: r.str('requested_by'),
                requestedAt: r.time('requested_at'),
              ),
              category: category,
              requestedByName: users[r.str('requested_by')]?.name ?? '—',
              requestedByRole: users[r.str('requested_by')]?.role ?? '',
            ),
    ];
  }

  Future<List<ClosedShift>> _closedShifts(
    DateTime since,
    String Function(String id) name,
  ) async => [
    for (final s in await _cloud.rows(
      'shifts',
      ['id', 'user_id', 'closed_at', 'variance'],
      where: [
        const Eq('status', 'closed'),
        Gte('closed_at', since.toIso8601String()),
      ],
    ))
      ClosedShift(
        shiftId: s.str('id'),
        userName: name(s.str('user_id')),
        closedAt: s.time('closed_at'),
        variance: s.integer('variance'),
      ),
  ];

  /// Payments voided since [since], oldest first.
  Future<List<PaymentVoided>> _paymentVoids(
    List<Map<String, Object?>> voids,
    DateTime since,
    String Function(String id) name,
  ) async {
    final recent = [
      for (final v in voids)
        if (v.str('target_type') == 'payment' &&
            !v.time('voided_at').isBefore(since))
          v,
    ];
    if (recent.isEmpty) return const [];
    final payments = {
      for (final p in await _cloud.rows(
        'payments',
        ['id', 'receipt_number', 'amount'],
        where: [
          InList('id', [for (final v in recent) v.str('target_id')]),
        ],
      ))
        p.str('id'): p,
    };
    return [
      for (final v in recent)
        if (payments[v.str('target_id')] case final p?)
          PaymentVoided(
            voidId: v.str('id'),
            receiptNumber: p.str('receipt_number'),
            amount: p.integer('amount'),
            reason: v.str('reason'),
            voidedBy: name(v.str('voided_by')),
            voidedAt: v.time('voided_at'),
          ),
    ]..sort((a, b) => a.voidedAt.compareTo(b.voidedAt));
  }

  /// Active rooms and beds with their active stays' paid-until (statuses
  /// only: no guest, not even an id), and active beds per category (in
  /// any room, as the desk's Prices counts them).
  Future<(List<BoardRoom>, Map<String, int>)> _rooms(
    Map<String, BedCategory> categories,
  ) async {
    final rooms = await _cloud.rows(
      'rooms',
      ['id', 'room_number'],
      where: const [Eq('is_active', true)],
    );
    final beds = await _cloud.rows(
      'beds',
      ['id', 'room_id', 'label', 'category_id', 'cleanliness'],
      where: const [Eq('is_active', true)],
      orderBy: 'label',
    );
    final bedsByCategory = <String, int>{};
    for (final b in beds) {
      final id = b.str('category_id');
      bedsByCategory[id] = (bedsByCategory[id] ?? 0) + 1;
    }
    final stays = {
      for (final s in await _cloud.rows(
        'stays',
        ['id', 'bed_id', 'paid_until'],
        where: const [Eq('status', 'active')],
      ))
        s.str('bed_id'): s,
    };
    final board = [
      for (final room in rooms)
        BoardRoom(
          id: room.str('id'),
          number: room.str('room_number'),
          beds: [
            for (final b in beds)
              if (b.str('room_id') == room.str('id'))
                if (categories[b.str('category_id')] case final category?)
                  BoardBed(
                    id: b.str('id'),
                    label: BedLabel.parse(b.str('label')),
                    categoryId: category.id,
                    categoryName: category.name,
                    pricePerNight: category.pricePerNight,
                    cleanliness: Cleanliness.parse(b.str('cleanliness')),
                    stay: switch (stays[b.str('id')]) {
                      final s? => BoardStay(
                        stayId: s.str('id'),
                        guestName: '',
                        guestPhone: '',
                        paidUntil: s.time('paid_until'),
                      ),
                      null => null,
                    },
                  ),
          ],
        ),
    ];
    return (board, bedsByCategory);
  }
}
