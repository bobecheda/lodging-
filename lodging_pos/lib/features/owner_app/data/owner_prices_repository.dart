import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../price_requests/domain/price_request.dart';
import '../../setup/domain/bed_category.dart';
import '../../setup/domain/prices_settings.dart';
import '../domain/owner_today.dart';
import 'owner_cloud.dart';
import 'owner_rows.dart';

/// A price edit the phone refused, or the cloud did (another edit got there
/// first); [message] is shown under the field.
final class PriceEditRefused implements Exception {
  const PriceEditRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The owner's prices from the phone (BR-2, Figma "06 Prices"): the same
/// rules as the desk (`price_request.dart`, `prices_settings.dart`), then
/// the cloud (`decide_price_request`, `change_prices`), stamped with the
/// server's time, this install's id and their audit rows. The desk pulls
/// them.
class OwnerPricesRepository {
  OwnerPricesRepository(this._cloud);

  final OwnerCloud _cloud;

  Future<DateTime> _serverNow() async =>
      DateTime.parse((await _cloud.rpc('server_time', const {}))! as String)
          .toUtc();

  Map<String, Object?> _audit({
    required String device,
    required String at,
    required String operation,
    required UserAccount owner,
    required String action,
    required String entity,
    required String entityId,
    required Map<String, Object?>? before,
    required Map<String, Object?> after,
  }) => {
    'id': const Uuid().v4(),
    'created_at': at,
    'updated_at': at,
    'device_id': device,
    'at': at,
    'operation_id': operation,
    'user_id': owner.id,
    'action': action,
    'entity': entity,
    'entity_id': entityId,
    'before_json': before == null ? null : jsonEncode(before),
    'after_json': jsonEncode(after),
  };

  /// The category as the cloud has it now.
  Future<BedCategory> _category(String id) async {
    final c = (await _cloud.rows(
      'bed_categories',
      ['id', 'name', 'price_per_night', 'sort_order', 'is_active'],
      where: [Eq('id', id)],
    )).single;
    return BedCategory(
      id: c.str('id'),
      name: c.str('name'),
      pricePerNight: c.integer('price_per_night'),
      sortOrder: c.integer('sort_order'),
      isActive: c['is_active']! as bool,
    );
  }

  /// Approves (`price.approve` with `price.update`) or, with a [note],
  /// rejects (`price.reject`) [request]. Throws [PriceRequestRuleViolation]
  /// (decided or withdrawn first: who and when), [StalePriceRequest],
  /// [OwnerCloudOffline] or [OwnerSignInRefused].
  Future<void> decide(
    UserAccount owner,
    OwnerPriceRequest request, {
    required bool approve,
    String? note,
  }) async {
    final at = await _serverNow();
    // The rules first, against the category as it is in the cloud now.
    final category = await _category(request.category.id);
    final decided = approve
        ? approvePriceRequest(
            request.request,
            category: category,
            by: owner,
            at: at,
          )
        : rejectPriceRequest(request.request, by: owner, note: note, at: at);
    final decision = decided.decision!;
    final id = const Uuid().v4();
    final device = await _cloud.deviceId();
    final stamp = at.toIso8601String();
    final operation = const Uuid().v4();
    final answer = await _cloud.rpc('decide_price_request', {
      'p_id': id,
      'p_request_id': request.id,
      'p_decision': decision.kind.code,
      'p_note': decision.note,
      'p_at': stamp,
      'p_device_id': device,
      'p_audit': [
        _audit(
          device: device,
          at: stamp,
          operation: operation,
          owner: owner,
          action: approve ? 'price.approve' : 'price.reject',
          entity: 'price_decisions',
          entityId: id,
          before: null,
          after: {
            'id': id,
            'created_at': stamp,
            'updated_at': stamp,
            'device_id': device,
            'request_id': request.id,
            'decision': decision.kind.code,
            'note': decision.note,
            'decided_by': owner.id,
            'decided_at': stamp,
          },
        ),
        if (approve)
          _audit(
            device: device,
            at: stamp,
            operation: operation,
            owner: owner,
            action: 'price.update',
            entity: 'bed_categories',
            entityId: category.id,
            before: {
              'id': category.id,
              'price_per_night': category.pricePerNight,
            },
            after: {
              'id': category.id,
              'price_per_night': request.request.newPrice,
            },
          ),
      ],
    });
    final reply = answer is Map ? answer : const {};
    switch (reply['status']) {
      case 'decided':
        return;
      case 'already_decided':
        throw PriceRequestRuleViolation(
          'Already decided by ${reply['decided_by_name'] ?? 'someone else'} · '
          '${formatDayDateComma(DateTime.parse(reply['decided_at'] as String).toUtc())} '
          '(${reply['decision'] == 'approved' ? 'approved' : 'rejected'}).',
        );
      case 'withdrawn' || 'already_withdrawn':
        throw const PriceRequestRuleViolation('This request was withdrawn.');
      case 'stale':
        final current = (reply['current_price']! as num).toInt();
        throw StalePriceRequest(
          staleError(
                request.request,
                BedCategory(
                  id: category.id,
                  name: category.name,
                  pricePerNight: current,
                  sortOrder: category.sortOrder,
                  isActive: category.isActive,
                ),
              ) ??
              'The price has changed. Reject this request or ask for a new '
                  'one.',
        );
      case 'missing':
        throw const PriceRequestRuleViolation(
          'This request isn’t in the cloud yet.',
        );
      default:
        throw const OwnerCloudRefused('The cloud gave an unexpected answer.');
    }
  }

  /// Changes [category]'s price to [newPrice] (`price.update`), over the
  /// price the owner was shown. Throws [PriceEditRefused] (the price rule,
  /// or another edit got there first: where and when), [NotPermitted],
  /// [OwnerCloudOffline] or [OwnerSignInRefused].
  Future<void> changePrice(
    UserAccount owner,
    BedCategory category, {
    required int? newPrice,
  }) async {
    requirePermission(owner, Permission.editPrices);
    final problem =
        priceError(newPrice) ??
        (newPrice == category.pricePerNight
            ? 'That’s already the price.'
            : null);
    if (problem != null) throw PriceEditRefused(problem);
    final at = await _serverNow();
    final device = await _cloud.deviceId();
    final stamp = at.toIso8601String();
    final answer = await _cloud.rpc('change_prices', {
      'p_changes': [
        {
          'category_id': category.id,
          'expected': category.pricePerNight,
          'price': newPrice,
        },
      ],
      'p_at': stamp,
      'p_device_id': device,
      'p_audit': [
        _audit(
          device: device,
          at: stamp,
          operation: const Uuid().v4(),
          owner: owner,
          action: 'price.update',
          entity: 'bed_categories',
          entityId: category.id,
          before: {
            'id': category.id,
            'price_per_night': category.pricePerNight,
          },
          after: {'id': category.id, 'price_per_night': newPrice},
        ),
      ],
    });
    final reply = answer is Map ? answer : const {};
    switch (reply['status']) {
      case 'changed':
        return;
      case 'stale':
        throw PriceEditRefused(
          priceMovedOnMessage(
            category.name,
            currentPrice: (reply['current_price']! as num).toInt(),
            at: DateTime.parse(reply['changed_at']! as String).toUtc(),
            where: priceChangedWhere(reply['changed_on'] as String?),
          ),
        );
      case 'missing':
        throw PriceEditRefused('${category.name} isn’t in the cloud yet.');
      default:
        throw const OwnerCloudRefused('The cloud gave an unexpected answer.');
    }
  }
}
