import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/owner_app/domain/owner_more.dart';
import 'package:lodging_pos/features/owner_app/domain/owner_today.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';

import '../../../helpers/fake_owner_cloud.dart' show auditDetailEntitiesAllowed;

void main() {
  final now = nairobiInstant(2026, 10, 25, 9, 30);

  group('the audit trail', () {
    test('every action reads as words, in a kind', () {
      expect(auditLabel('stay.check_in'), 'Checked a guest in');
      expect(auditKindOf('stay.check_in'), AuditKind.stays);
      expect(auditLabel('price.update'), 'Changed a price');
      expect(auditKindOf('price.update'), AuditKind.prices);
      expect(auditLabel('refund.approve'), 'Approved a refund');
      expect(auditKindOf('refund.pay'), AuditKind.money);
      expect(auditKindOf('user.login_failed'), AuditKind.signIns);
      expect(
        auditLabel('user.password_from_cloud'),
        'Desk took the password set on the phone',
      );
      expect(auditKindOf('user.change_password'), AuditKind.staff);
      // Something newer than this app: its own name, under Other.
      expect(auditLabel('thing.happened'), 'thing.happened');
      expect(auditKindOf('thing.happened'), AuditKind.other);
      expect(
        auditActionsOf(AuditKind.money),
        containsAll(['payment.create', 'void.create', 'shift.close']),
      );
    });

    test('details only for entities without guest data; refunds by their '
        'own named columns', () {
      expect(auditDetailEntities, auditDetailEntitiesAllowed);
      expect(auditDetailEntities, isNot(contains('refunds')));
      expect(
        auditDetail(
          entity: 'bed_categories',
          action: 'price.update',
          before: '{"id":"c-1","name":"Deluxe","price_per_night":700}',
          after: '{"id":"c-1","name":"Deluxe","price_per_night":750}',
        ),
        'Deluxe: KES 700 → KES 750',
      );
      expect(
        auditDetail(
          entity: 'refund_decisions',
          action: 'refund.reject',
          before: null,
          after: '{"decision":"rejected","note":"Guest stays on"}',
        ),
        'Rejected · “Guest stays on”',
      );
      expect(
        auditDetail(
          entity: 'price_decisions',
          action: 'price.approve',
          before: null,
          after: '{"decision":"approved","note":null}',
        ),
        'Approved',
      );
      expect(
        auditDetail(
          entity: 'voids',
          action: 'void.create',
          before: null,
          after: '{"target_type":"payment","reason":"Entered twice"}',
        ),
        'Payment voided · “Entered twice”',
      );
      expect(
        auditDetail(
          entity: 'shifts',
          action: 'shift.close',
          before: null,
          after: '{"counted_cash":4700,"variance":-300}',
        ),
        'Counted KES 4,700 · KES 300 short',
      );
      expect(
        auditDetail(
          entity: 'shifts',
          action: 'shift.open',
          before: null,
          after: '{"opening_float":500}',
        ),
        'Float KES 500',
      );
      expect(
        auditDetail(
          entity: 'guests',
          action: 'guest.create',
          before: null,
          after: '{"full_name":"x"}',
        ),
        isNull,
      );
      expect(
        refundDetail(amount: 1400, method: PaymentMethod.cash, status: 'Paid'),
        'KES 1,400 · Paid · Cash',
      );
      expect(
        refundDetail(amount: 1400, method: null, status: 'Waiting'),
        'KES 1,400 · Waiting',
      );
    });

    test('where: on the desk, or on the phone', () {
      expect(whereDone('dev-1', deskIds: {'dev-1'}), 'on the desk');
      expect(whereDone('phone-install-1', deskIds: {'dev-1'}), 'on the phone');
    });
  });

  test('a shift’s difference says short or over in words', () {
    expect(varianceLine(-300), 'KES 300 short');
    expect(varianceLine(200), 'KES 200 over');
    expect(varianceLine(0), 'Exact');
  });

  test('the account card’s desk line', () {
    DeskStatus desk(DateTime? pushed) => DeskStatus(
      deviceId: 'dev-1',
      reportedAt: now,
      lastPushAt: pushed,
      pending: 0,
    );
    expect(
      deskSyncedLine([desk(now.subtract(const Duration(minutes: 2)))], now),
      'Desk last synced 2 min ago',
    );
    expect(deskSyncedLine([desk(now)], now), 'Desk last synced just now');
    expect(
      deskSyncedLine([desk(now.subtract(const Duration(hours: 3)))], now),
      'Desk last synced today 06:30',
    );
    expect(deskSyncedLine([desk(null)], now), 'The desk hasn’t synced yet.');
    expect(
      deskSyncedLine(const [], now),
      'The desk isn’t connected to the cloud yet.',
    );
  });
}
