import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';

/// The Now strip is a summary, never a list (brief, "Bed board — fixes
/// after the first build", 25 Nov 2026).
void main() {
  group('how long an overstay has run', () {
    test('under 24 h in hours, from 24 h in days', () {
      expect(overstayLength(const Duration(minutes: 40)), '40 min');
      expect(overstayLength(const Duration(hours: 2, minutes: 59)), '2 h');
      expect(overstayLength(const Duration(hours: 23, minutes: 59)), '23 h');
      expect(overstayLength(const Duration(hours: 24)), '1 day');
      expect(overstayLength(const Duration(days: 32, hours: 5)), '32 days');
    });
  });

  group('the overstay card shows at most 3 rows', () {
    test('3 or fewer: all, no "more"', () {
      expect(nowRows(2), (shown: 2, more: 0));
      expect(nowRows(3), (shown: 3, more: 0));
    });

    test('more than 3: the 3 oldest, then "+ N more"', () {
      expect(nowRows(11), (shown: 3, more: 8));
    });
  });

  group('To clean chips fit in two lines, then "+ N more"', () {
    // Chips 50 wide, 8 apart: 4 fit in a 224 line (4 × 50 + 3 × 8).
    double more(int n) => 70;
    int fit(int count, {double width = 224}) => chipsThatFit(
      widths: List.filled(count, 50),
      maxWidth: width,
      gap: 8,
      lines: 2,
      moreWidth: more,
    );

    test('all of them when they fit', () {
      expect(fit(0), 0);
      expect(fit(5), 5);
      expect(fit(8), 8);
    });

    test('too many: as many as fit with the "more" chip on the last line', () {
      // Line 2 holds 2 chips (108) + 8 + the 70 more chip = 186 ≤ 224; a
      // third chip would need 244.
      expect(fit(14), 6);
    });

    test('a narrow card still shows "more" alone', () {
      expect(fit(3, width: 60), 1);
    });

    test('chips of different widths wrap where they no longer fit', () {
      expect(
        chipsThatFit(
          widths: const [100, 100, 100, 60, 60],
          maxWidth: 210,
          gap: 10,
          lines: 2,
          moreWidth: more,
        ),
        3,
      );
    });
  });
}
