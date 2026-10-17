import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../data/guests_repository.dart';
import '../domain/guest.dart';

part 'guests_providers.g.dart';

@Riverpod(keepAlive: true)
GuestsRepository guestsRepository(Ref ref) => GuestsRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
);

/// The 30 guests registered or corrected most recently, newest first. A
/// drift `watch()`: updates itself after every register and correction.
@riverpod
Stream<List<Guest>> recentGuests(Ref ref) =>
    ref.watch(guestsRepositoryProvider).watchRecent();

/// Matches for what's typed in the search box (empty under 3 characters);
/// also watched, so a correction shows at once.
@riverpod
Stream<List<Guest>> guestSearch(Ref ref, String text) =>
    ref.watch(guestsRepositoryProvider).watchSearch(GuestQuery.parse(text));

/// Other guests registered with [phone] (stored form), for the form's
/// duplicate notice.
@riverpod
Future<List<Guest>> guestsWithPhone(Ref ref, String phone, String? exceptId) =>
    ref.watch(guestsRepositoryProvider).withPhone(phone, exceptId: exceptId);

/// One guest, watched so the opened guest updates after a correction.
@riverpod
Stream<Guest> guestById(Ref ref, String id) =>
    ref.watch(guestsRepositoryProvider).watchGuest(id);
