import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/shifts/domain/cash_review.dart';

UserAccount user(String id, Role role) => UserAccount(
  id: id,
  fullName: id,
  username: id,
  role: role,
  isActive: true,
  mustChangePassword: false,
);

final owner = user('owner', Role.owner);
final grace = user('grace', Role.supervisor);
final otherSupervisor = user('otto', Role.supervisor);
final mary = user('mary', Role.receptionist);
final tom = user('tom', Role.receptionist);

ReviewTarget shiftOf(
  UserAccount shiftUser, {
  UserAccount? closer,
  bool needsReview = true,
}) => ReviewTarget(
  kind: ReviewTargetKind.shift,
  id: 's-1',
  needsReview: needsReview,
  named: [shiftUser, ?closer],
);

ReviewTarget countBy(UserAccount counter, {required UserAccount present}) =>
    ReviewTarget(
      kind: ReviewTargetKind.drawerEvent,
      id: 'd-1',
      needsReview: true,
      named: [counter, present],
      counter: counter,
    );

void main() {
  group('the status is derived (B3)', () {
    test('no review needed, awaiting, approved, rejected', () {
      expect(reviewStatus(needsReview: false), ReviewStatus.notNeeded);
      expect(reviewStatus(needsReview: true), ReviewStatus.awaiting);
      expect(
        reviewStatus(needsReview: true, decision: ReviewDecision.approved),
        ReviewStatus.approved,
      );
      expect(
        reviewStatus(needsReview: true, decision: ReviewDecision.rejected),
        ReviewStatus.rejected,
      );
    });
  });

  group('who decides', () {
    test('a receptionist never decides', () {
      expect(can(mary, Permission.reviewCash), isFalse);
      expect(
        () => checkReview(
          shiftOf(tom),
          by: mary,
          decision: ReviewDecision.approved,
        ),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('a receptionist’s shift: the supervisor or the owner', () {
      expect(reviewBlocker(shiftOf(mary), grace), isNull);
      expect(reviewBlocker(shiftOf(mary), owner), isNull);
    });

    test('nobody decides an item that names them: shift user or closer', () {
      expect(
        reviewBlocker(shiftOf(mary, closer: grace), grace),
        'You’re named in this, so someone else decides.',
      );
      expect(reviewBlocker(shiftOf(mary, closer: grace), owner), isNull);
    });

    test('a supervisor’s shift: the owner only, never another supervisor', () {
      expect(
        reviewBlocker(shiftOf(otherSupervisor), grace),
        'A supervisor is named in this: the owner decides.',
      );
      expect(reviewBlocker(shiftOf(otherSupervisor), owner), isNull);
    });

    test('a supervisor’s count: the owner only', () {
      final t = countBy(grace, present: mary);
      expect(reviewBlocker(t, grace), isNotNull);
      expect(
        reviewBlocker(countBy(otherSupervisor, present: mary), grace),
        'A supervisor is named in this: the owner decides.',
      );
      expect(reviewBlocker(t, owner), isNull);
    });

    test('a supervisor present at the owner’s count: still the owner’s', () {
      final t = countBy(owner, present: grace);
      expect(reviewBlocker(t, owner), isNull);
      expect(reviewBlocker(t, grace), isNotNull);
    });

    test('the owner’s own count: the owner decides it, nobody else', () {
      final t = countBy(owner, present: mary);
      expect(reviewBlocker(t, owner), isNull);
      expect(
        reviewBlocker(t, grace),
        'The owner decides gaps from the owner’s own counts.',
      );
    });

    test('nothing to review, or decided once', () {
      expect(
        reviewBlocker(shiftOf(mary, needsReview: false), grace),
        'Nothing to review here.',
      );
      expect(
        reviewBlocker(shiftOf(mary), grace, decided: ReviewDecision.approved),
        'Already decided.',
      );
    });
  });

  group('the reason', () {
    test('required to reject, at most 200 characters; not to approve', () {
      expect(
        () => checkReview(
          shiftOf(mary),
          by: grace,
          decision: ReviewDecision.rejected,
          reason: '  ',
        ),
        throwsA(
          isA<CashReviewProblem>().having(
            (e) => e.message,
            'message',
            'Say why you reject it.',
          ),
        ),
      );
      expect(
        () => checkReview(
          shiftOf(mary),
          by: grace,
          decision: ReviewDecision.rejected,
          reason: 'x' * 201,
        ),
        throwsA(isA<CashReviewProblem>()),
      );
      checkReview(
        shiftOf(mary),
        by: grace,
        decision: ReviewDecision.rejected,
        reason: 'The reason doesn’t explain KES 300',
      );
      checkReview(shiftOf(mary), by: grace, decision: ReviewDecision.approved);
    });

    test('a blocker is refused by the check too', () {
      expect(
        () => checkReview(
          shiftOf(grace),
          by: grace,
          decision: ReviewDecision.approved,
        ),
        throwsA(isA<CashReviewProblem>()),
      );
    });
  });

  test('the audit actions name the target', () {
    expect(
      reviewAction(ReviewTargetKind.shift, ReviewDecision.approved),
      'shift.review_approve',
    );
    expect(
      reviewAction(ReviewTargetKind.drawerEvent, ReviewDecision.rejected),
      'drawer.review_reject',
    );
  });
}
