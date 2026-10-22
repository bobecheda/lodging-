import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/price_requests/domain/price_request.dart';
import 'package:lodging_pos/features/setup/domain/bed_category.dart';

DateTime oct(int day, int hour, [int minute = 0]) =>
    nairobiInstant(2026, 10, day, hour, minute);

const owner = UserAccount(
  id: 'owner',
  fullName: 'Amina Owner',
  username: 'owner',
  role: Role.owner,
  isActive: true,
  mustChangePassword: false,
);

const supervisor = UserAccount(
  id: 'supervisor',
  fullName: 'Grace Supervisor',
  username: 'supervisor',
  role: Role.supervisor,
  isActive: true,
  mustChangePassword: false,
);

const otherSupervisor = UserAccount(
  id: 'supervisor-2',
  fullName: 'Paul Supervisor',
  username: 'paul',
  role: Role.supervisor,
  isActive: true,
  mustChangePassword: false,
);

const desk = UserAccount(
  id: 'desk',
  fullName: 'Desk Clerk',
  username: 'desk',
  role: Role.receptionist,
  isActive: true,
  mustChangePassword: false,
);

BedCategory deluxe({int price = 700, bool active = true}) => BedCategory(
  id: 'deluxe',
  name: 'Deluxe',
  pricePerNight: price,
  sortOrder: 2,
  isActive: active,
);

PriceRequest ask({
  BedCategory? category,
  int newPrice = 750,
  String? reason,
  UserAccount by = supervisor,
  PriceRequest? open,
}) => requestPriceChange(
  category ?? deluxe(),
  id: 'req-1',
  newPrice: newPrice,
  reason: reason,
  by: by,
  at: oct(21, 9, 15),
  open: open,
);

Matcher violation(String message) => throwsA(
  isA<PriceRequestRuleViolation>().having((e) => e.message, 'message', message),
);

void main() {
  group('asking (the supervisor)', () {
    test('keeps the price it was made against; waiting for the owner', () {
      final r = ask(reason: '  Others nearby charge 800  ');
      expect((r.categoryId, r.oldPrice, r.newPrice), ('deluxe', 700, 750));
      expect(r.reason, 'Others nearby charge 800');
      expect((r.requestedBy, r.requestedAt), ('supervisor', oct(21, 9, 15)));
      expect(r.status, PriceRequestStatus.waiting);
      expect(r.change, 50);
    });

    test('a blank reason is no reason', () {
      expect(ask(reason: '   ').reason, isNull);
      expect(ask().reason, isNull);
    });

    test('the new price: the owner’s rule (KES 1–100,000), and not the '
        'price it already is', () {
      expect(requestedPriceError(null, currentPrice: 700), 'Enter a price.');
      expect(
        requestedPriceError(0, currentPrice: 700),
        'The price must be at least KES 1.',
      );
      expect(
        requestedPriceError(100001, currentPrice: 700),
        'The price can be at most KES 100,000.',
      );
      expect(
        requestedPriceError(700, currentPrice: 700),
        'That’s already the price.',
      );
      expect(requestedPriceError(650, currentPrice: 700), isNull);
      expect(
        () => ask(newPrice: 700),
        throwsA(
          isA<InvalidRequestedPrice>().having(
            (e) => e.message,
            'message',
            'That’s already the price.',
          ),
        ),
      );
    });

    test('a reason of up to 200 characters', () {
      expect(requestReasonError('x' * 200), isNull);
      expect(
        requestReasonError('x' * 201),
        'Keep the reason under 200 characters.',
      );
      expect(
        () => ask(reason: 'x' * 201),
        violation('Keep the reason under 200 characters.'),
      );
    });

    test('one open request per category', () {
      expect(
        () => ask(open: ask()),
        violation('Deluxe already has a request waiting for the owner.'),
      );
    });

    test('not for a closed category', () {
      expect(
        () => ask(category: deluxe(active: false)),
        violation('Deluxe is closed.'),
      );
    });

    test('only the supervisor asks; the owner changes prices directly', () {
      expect(() => ask(by: owner), throwsA(isA<NotPermitted>()));
      expect(() => ask(by: desk), throwsA(isA<NotPermitted>()));
    });
  });

  group('withdrawing', () {
    test('the supervisor withdraws their own waiting request', () {
      final r = withdrawPriceRequest(ask(), by: supervisor, at: oct(21, 10));
      expect(r.status, PriceRequestStatus.withdrawn);
      expect(r.withdrawal!.by, 'supervisor');
      expect(r.withdrawal!.at, oct(21, 10));
      expect(r.withdrawal!.reason, isNull);
      expect(r.withdrawal!.categoryClosed, isFalse);
    });

    test('not someone else’s, and not once decided or withdrawn', () {
      expect(
        () => withdrawPriceRequest(ask(), by: otherSupervisor, at: oct(21, 10)),
        violation('Only the supervisor who asked can withdraw it.'),
      );
      final approved = approvePriceRequest(
        ask(),
        category: deluxe(),
        by: owner,
        at: oct(21, 10),
      );
      expect(
        () => withdrawPriceRequest(approved, by: supervisor, at: oct(21, 11)),
        violation('The owner has already decided this request.'),
      );
      final gone = withdrawPriceRequest(ask(), by: supervisor, at: oct(21, 10));
      expect(
        () => withdrawPriceRequest(gone, by: supervisor, at: oct(21, 11)),
        violation('This request was withdrawn.'),
      );
    });

    test('closing the category withdraws it, by the owner, “Category '
        'closed”', () {
      final r = withdrawForClosedCategory(ask(), by: owner, at: oct(21, 12));
      expect(r.status, PriceRequestStatus.withdrawn);
      expect(r.withdrawal!.by, 'owner');
      expect(r.withdrawal!.reason, 'Category closed');
      expect(r.withdrawal!.categoryClosed, isTrue);
      expect(
        () => withdrawForClosedCategory(ask(), by: supervisor, at: oct(21, 12)),
        throwsA(isA<NotPermitted>()),
      );
    });
  });

  group('deciding (the owner)', () {
    test('approve: as asked', () {
      final r = approvePriceRequest(
        ask(),
        category: deluxe(),
        by: owner,
        at: oct(21, 10),
      );
      expect(r.status, PriceRequestStatus.approved);
      expect(r.decision!.decidedBy, 'owner');
      expect(r.decision!.note, isNull);
    });

    test('approve: refused once the price changed since the request', () {
      expect(
        () => approvePriceRequest(
          ask(),
          category: deluxe(price: 720),
          by: owner,
          at: oct(21, 10),
        ),
        throwsA(
          isA<StalePriceRequest>().having(
            (e) => e.message,
            'message',
            'Deluxe is now KES 720, not 700. Reject this request or ask for '
                'a new one.',
          ),
        ),
      );
      expect(staleError(ask(), deluxe(price: 720)), isNotNull);
      expect(staleError(ask(), deluxe()), isNull);
    });

    test('reject: a reason is required', () {
      expect(
        () => rejectPriceRequest(ask(), by: owner, note: '  ', at: oct(21, 10)),
        violation('Give a reason for rejecting the price change.'),
      );
      final r = rejectPriceRequest(
        ask(),
        by: owner,
        note: ' Too soon after the last change ',
        at: oct(21, 10),
      );
      expect(r.status, PriceRequestStatus.rejected);
      expect(r.decision!.note, 'Too soon after the last change');
    });

    test('once, and never a withdrawn request', () {
      final rejected = rejectPriceRequest(
        ask(),
        by: owner,
        note: 'No',
        at: oct(21, 10),
      );
      expect(
        () => approvePriceRequest(
          rejected,
          category: deluxe(),
          by: owner,
          at: oct(21, 11),
        ),
        violation('This request has already been decided.'),
      );
      final gone = withdrawPriceRequest(ask(), by: supervisor, at: oct(21, 10));
      expect(
        () => rejectPriceRequest(gone, by: owner, note: 'No', at: oct(21, 11)),
        violation('This request was withdrawn.'),
      );
    });

    test('only the owner decides', () {
      expect(
        () => approvePriceRequest(
          ask(),
          category: deluxe(),
          by: supervisor,
          at: oct(21, 10),
        ),
        throwsA(isA<NotPermitted>()),
      );
      expect(
        () => rejectPriceRequest(
          ask(),
          by: supervisor,
          note: 'No',
          at: oct(21, 10),
        ),
        throwsA(isA<NotPermitted>()),
      );
    });
  });

  test('the change, signed: +50 and −50', () {
    expect(formatPriceChange(50), '+50');
    expect(formatPriceChange(-50), '−50');
    expect(formatPriceChange(1250), '+1,250');
  });
}
