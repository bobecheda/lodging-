import 'database.dart';

/// `device_id` stamped on seed rows. The cloud seeds the same rows with the
/// same ids and device id, so sync never duplicates them.
const seedDeviceId = 'seed';

/// Fixed ids for the seeded bed categories (BR-2).
abstract final class SeedIds {
  static const vip = '28a0fbdd-ed0b-4d51-80e0-90bf851fc142';
  static const deluxe = 'fb699568-46ad-4274-b28c-0d4f2545c5c6';
  static const comfort = 'cdc98a60-8cb9-4791-a0a9-66c4493d132d';
  static const normal = 'ccf717df-8854-4ff5-b1f0-aec27d05147d';
}

/// Writes the v1 seed rows. Runs once, inside `onCreate`.
///
/// Seed rows have no audit_log or outbox rows. No user is seeded: the
/// first-run setup screen creates the admin.
Future<void> seedV1(
  AppDatabase db, {
  required String deviceId,
  required DateTime now,
}) async {
  await db
      .into(db.device)
      .insert(DeviceCompanion.insert(deviceId: deviceId, createdAt: now));
  await db
      .into(db.receiptCounter)
      .insert(
        ReceiptCounterCompanion.insert(deviceId: deviceId, nextNumber: 1),
      );

  const settings = {
    'lodging_name': '',
    'block_hours': '12',
    'grace_minutes': '60',
    'receipt_prefix': 'R',
  };
  await db.batch((b) {
    b.insertAll(db.settings, [
      for (final MapEntry(:key, :value) in settings.entries)
        SettingsCompanion.insert(
          key: key,
          value: value,
          createdAt: now,
          updatedAt: now,
          deviceId: seedDeviceId,
        ),
    ]);
    b.insertAll(db.bedCategories, [
      for (final (i, (id, name, price)) in const [
        (SeedIds.vip, 'VIP', 1000),
        (SeedIds.deluxe, 'Deluxe', 700),
        (SeedIds.comfort, 'Comfort', 600),
        (SeedIds.normal, 'Normal', 500),
      ].indexed)
        BedCategoriesCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          deviceId: seedDeviceId,
          name: name,
          pricePerBlock: price,
          sortOrder: i + 1,
        ),
    ]);
  });
}
