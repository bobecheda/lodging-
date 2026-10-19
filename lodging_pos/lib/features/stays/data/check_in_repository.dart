import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock_time.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../guests/data/guests_repository.dart';
import '../../guests/domain/guest.dart';
import '../../payments/domain/payment_rules.dart';
import '../../payments/data/payment_writes.dart';
import '../../setup/domain/prices_settings.dart';
import '../../setup/domain/rooms.dart';
import '../../shifts/domain/shift_rules.dart';
import '../domain/check_in.dart';
import '../domain/stay_rules.dart';

/// The request failed [validateCheckIn].
class InvalidCheckIn implements Exception {
  const InvalidCheckIn(this.errors);
  final Map<CheckInField, String> errors;

  @override
  String toString() => errors.values.join(' ');
}

/// Something changed since the screen showed it (a bed was let or closed,
/// a price or the date moved): [message] says what and what to do.
class CheckInRefused implements Exception {
  const CheckInRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Since the new guest's form was filled in, [guests] were registered with
/// the same phone. Saving again (with them seen) registers the new guest
/// anyway: families share phones.
class PhoneNowShared implements Exception {
  const PhoneNowShared(this.guests);
  final List<Guest> guests;

  @override
  String toString() =>
      'Since you started, ${guests.map((g) => g.fullName).join(', ')} '
      '${guests.length == 1 ? 'was' : 'were'} registered with this phone. '
      'Choose them, or save again to register a new guest.';
}

/// A saved check-in: what step 4 and the receipt (FD-6) show.
final class CheckInResult {
  const CheckInResult({
    required this.paymentId,
    required this.receiptNumber,
    required this.stayIds,
    required this.roomNumber,
    required this.labels,
    required this.total,
    required this.method,
    required this.mpesaCode,
    required this.paidUntil,
  });

  final String paymentId;
  final String receiptNumber;
  final List<String> stayIds;
  final String roomNumber;
  final List<BedLabel> labels;

  /// Whole KES.
  final int total;
  final PaymentMethod method;

  /// As stored (capitals); null for cash.
  final String? mpesaCode;

  /// UTC.
  final DateTime paidUntil;
}

/// Check-in (FD-4) with its payment (FD-5), in one transaction through
/// writeWithAudit: the new guest if any (`guest.create`), one stay and one
/// charge per bed (`stay.check_in`), one payment for all of them
/// (`payment.create`), and the next receipt number. Everything the screen
/// showed is checked again inside the transaction; if anything fails,
/// nothing is saved and the beds stay Available (BR-5).
class CheckInRepository {
  CheckInRepository(this._db, this._audit, this._guests);

  final AppDatabase _db;
  final AuditWriter _audit;
  final GuestsRepository _guests;

  /// Open rooms with every bed, closed ones included (so the screen can say
  /// why Bed B can't be added), each with its category's current price and
  /// whether it has a guest. A drift `watch()`, so a bed let or cleaned
  /// elsewhere updates the choices at once.
  Stream<List<RoomSummary>> watchRooms() {
    final query =
        _db.select(_db.rooms).join([
            innerJoin(_db.beds, _db.beds.roomId.equalsExp(_db.rooms.id)),
            innerJoin(
              _db.bedCategories,
              _db.bedCategories.id.equalsExp(_db.beds.categoryId),
            ),
            leftOuterJoin(
              _db.stays,
              _db.stays.bedId.equalsExp(_db.beds.id) &
                  _db.stays.status.equals('active'),
            ),
          ])
          ..where(_db.rooms.isActive.equals(true))
          ..orderBy([OrderingTerm.asc(_db.beds.label)]);
    return query.watch().map((rows) {
      final rooms = <String, (RoomRow, List<BedSummary>)>{};
      for (final row in rows) {
        final room = row.readTable(_db.rooms);
        final bed = row.readTable(_db.beds);
        final category = row.readTable(_db.bedCategories);
        rooms
            .putIfAbsent(room.id, () => (room, []))
            .$2
            .add(
              BedSummary(
                id: bed.id,
                label: BedLabel.parse(bed.label),
                categoryId: category.id,
                categoryName: category.name,
                pricePerNight: category.pricePerNight,
                cleanliness: Cleanliness.parse(bed.cleanliness),
                isActive: bed.isActive,
                hasActiveStay: row.readTableOrNull(_db.stays) != null,
              ),
            );
      }
      return [
        for (final (room, beds) in rooms.values)
          RoomSummary(
            id: room.id,
            number: room.roomNumber,
            floor: room.floor,
            notes: room.notes,
            isActive: room.isActive,
            beds: beds,
          ),
      ]..sort((a, b) => compareRoomNumbers(a.number, b.number));
    });
  }

  /// The checkout time setting, watched, for the dates the screen shows.
  Stream<ClockTime> watchCheckoutTime() =>
      (_db.select(_db.settings)
            ..where((s) => s.key.equals(SettingKeys.checkoutTime)))
          .watchSingleOrNull()
          .map(
            (row) =>
                SettingsInput.fromStored({if (row != null) row.key: row.value})
                    .checkoutTime,
          );

  /// [guestId]'s earlier check-ins; both beds of one check-in share a
  /// check-in time, so they count once.
  Future<GuestHistory> guestHistory(String guestId) async {
    final count = _db.stays.checkInAt.count(distinct: true);
    final last = _db.stays.checkInAt.max();
    final row =
        await (_db.selectOnly(_db.stays)
              ..addColumns([count, last])
              ..where(_db.stays.guestId.equals(guestId)))
            .getSingle();
    return GuestHistory(
      stays: row.read(count) ?? 0,
      lastCheckIn: row.read(last),
    );
  }

  /// Saves [r] for [user]. Throws [NotPermitted], [NoOpenShift] (the user
  /// has no open shift of their own on this device), [InvalidCheckIn],
  /// [InvalidGuest] (a new guest's ID is taken), [PhoneNowShared] or
  /// [CheckInRefused].
  Future<CheckInResult> checkIn(UserAccount user, CheckInRequest r) async {
    requirePermission(user, Permission.checkIn);
    final guest = r.guest;
    if (guest is NewGuest) requirePermission(user, Permission.registerGuests);

    return _audit.writeWithAudit(
      action: 'stay.check_in',
      userId: user.id,
      body: (w) async {
        // BR-12: the payment goes into the user's own open shift.
        final shift = await ownOpenShift(_db, w, user.id);
        if (shift == null) throw const NoOpenShift();

        final code = r.method == PaymentMethod.paybill && r.mpesaCode != null
            ? normalizeMpesaCode(r.mpesaCode!)
            : r.mpesaCode;
        final errors = validateCheckIn(
          r,
          codeUsedOn: code == null || code.trim().isEmpty
              ? null
              : await mpesaCodeUse(_db, code),
        );
        if (errors.isNotEmpty) throw InvalidCheckIn(errors);

        // BR-5, again now: each bed active, without a guest and clean, all
        // in one room.
        final beds = <BedSummary>[];
        final roomIds = <String>{};
        String? roomNumber;
        for (final shown in r.shown.beds) {
          final row = await (_db.select(_db.beds).join([
            innerJoin(
              _db.bedCategories,
              _db.bedCategories.id.equalsExp(_db.beds.categoryId),
            ),
            innerJoin(_db.rooms, _db.rooms.id.equalsExp(_db.beds.roomId)),
          ])..where(_db.beds.id.equals(shown.bedId))).getSingleOrNull();
          if (row == null) {
            throw const CheckInRefused('That bed no longer exists.');
          }
          final bed = row.readTable(_db.beds);
          final category = row.readTable(_db.bedCategories);
          final room = row.readTable(_db.rooms);
          final taken =
              await (_db.select(_db.stays)..where(
                    (s) => s.bedId.equals(bed.id) & s.status.equals('active'),
                  ))
                  .getSingleOrNull();
          final summary = BedSummary(
            id: bed.id,
            label: BedLabel.parse(bed.label),
            categoryId: category.id,
            categoryName: category.name,
            pricePerNight: category.pricePerNight,
            cleanliness: Cleanliness.parse(bed.cleanliness),
            isActive: bed.isActive && room.isActive,
            hasActiveStay: taken != null,
          );
          final blocker = letBlocker(
            summary,
            taken == null ? Occupancy.available : Occupancy.occupied,
          );
          if (blocker != null) {
            throw CheckInRefused(
              'Room ${room.roomNumber} · $blocker. Choose another bed.',
            );
          }
          beds.add(summary);
          roomIds.add(room.id);
          roomNumber = room.roomNumber;
        }
        if (roomIds.length > 1) {
          throw const CheckInRefused(
            'Both beds must be in the same room. Choose again.',
          );
        }

        // What a save now records, against what the screen showed.
        final settings = SettingsInput.fromStored({
          for (final s in await _db.select(_db.settings).get()) s.key: s.value,
        });
        final now = quoteCheckIn(
          checkInAt: w.now,
          nights: r.shown.nights,
          checkout: settings.checkoutTime,
          beds: [
            for (final b in beds)
              LetBed(
                bedId: b.id,
                categoryId: b.categoryId,
                categoryName: b.categoryName,
                pricePerNight: b.pricePerNight,
              ),
          ],
        );
        final change = quoteChange(r.shown, now);
        if (change != null) throw CheckInRefused(change);

        final guestId = switch (guest) {
          ReturningGuest(:final guestId) => await _returning(guestId),
          NewGuest() => await _register(w, guest),
        };

        final receipt = await takeReceiptNumber(_db, w, settings.receiptPrefix);
        final stays = <String, StayRow>{};
        final labels = {for (final b in beds) b.id: b.label};
        for (final planned in now.plan.stays) {
          stays[planned.bedId] = await w.insert(
            _db.stays,
            StaysCompanion.insert(
              guestId: guestId,
              bedId: planned.bedId,
              checkInAt: w.now,
              paidUntil: planned.charge.periodEnd,
              status: 'active',
              checkedInBy: user.id,
              // Kept as let (v3), so a receipt survives a renumbering.
              roomNumber: roomNumber!,
              bedLabel: labels[planned.bedId]!.code,
            ),
          );
        }
        final payment = await w.insert(
          _db.payments,
          PaymentsCompanion.insert(
            receiptNumber: receipt,
            shiftId: shift.id,
            receivedBy: user.id,
            receivedAt: w.now,
            amount: now.total,
            method: r.method.code,
            mpesaCode: Value(r.method == PaymentMethod.paybill ? code : null),
          ),
          action: 'payment.create',
        );
        for (final planned in now.plan.stays) {
          final c = planned.charge;
          await w.insert(
            _db.stayCharges,
            StayChargesCompanion.insert(
              stayId: stays[planned.bedId]!.id,
              paymentId: payment.id,
              kind: c.kind.code,
              nights: c.nights,
              pricePerNight: c.pricePerNight,
              amount: c.amount,
              periodStart: c.periodStart,
              periodEnd: c.periodEnd,
              categoryId: c.categoryId,
              categoryName: c.categoryName,
            ),
          );
        }

        return CheckInResult(
          paymentId: payment.id,
          receiptNumber: receipt,
          stayIds: [for (final s in stays.values) s.id],
          roomNumber: roomNumber!,
          labels: [for (final b in beds) b.label],
          total: now.total,
          method: r.method,
          mpesaCode: payment.mpesaCode,
          paidUntil: now.paidUntil,
        );
      },
    );
  }

  Future<String> _returning(String guestId) async {
    final row = await (_db.select(
      _db.guests,
    )..where((g) => g.id.equals(guestId))).getSingleOrNull();
    if (row == null) {
      throw const CheckInRefused(
        'That guest no longer exists. Find them again.',
      );
    }
    return row.id;
  }

  /// `guest.create`, with FD-3's checks run again inside the transaction.
  Future<String> _register(AuditedWrites w, NewGuest guest) async {
    final form = guest.form.normalized();
    await _guests.requireFreeId(form);
    final sharing = await _guests.withPhone(form.phone);
    final news = [
      for (final g in sharing)
        if (!guest.phoneSharedWith.contains(g.id)) g,
    ];
    if (news.isNotEmpty) throw PhoneNowShared(news);
    final row = await w.insert(
      _db.guests,
      GuestsCompanion.insert(
        fullName: form.fullName,
        phone: form.phone,
        idType: Value(form.idType?.code),
        idNumber: Value(form.idNumber.isEmpty ? null : form.idNumber),
      ),
      action: 'guest.create',
    );
    return row.id;
  }
}
