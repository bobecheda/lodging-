import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/theme/theme.dart';
import 'package:lodging_pos/app/widgets/bed_status_tile.dart';
import 'package:lodging_pos/app/widgets/block_stepper.dart';
import 'package:lodging_pos/app/widgets/buttons.dart';
import 'package:lodging_pos/app/widgets/money_input.dart';
import 'package:lodging_pos/app/widgets/notes.dart';
import 'package:lodging_pos/app/widgets/segmented_choice.dart';
import 'package:lodging_pos/core/money/kes.dart';

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildLodgingTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  group('KesInputFormatter', () {
    TextEditingValue format(String text) => const KesInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('groups thousands and keeps whole numbers only', () {
      expect(format('2000').text, '2,000');
      expect(format('1234567').text, '1,234,567');
      expect(format('12.50').text, '1,250');
      expect(format('00700').text, '700');
      expect(format('abc').text, '');
      expect(format('0').text, '0');
    });

    test('what it shows parses back to the amount', () {
      expect(parseKes(format('1500').text), 1500);
    });
  });

  testWidgets('MoneyInput shows the KES prefix and grouped value', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      MoneyInput(
        label: 'Opening cash float',
        controller: controller,
        fieldKey: const ValueKey('money'),
      ),
    );
    expect(find.text('KES'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('money')), '25000');
    expect(controller.text, '25,000');
  });

  testWidgets('BlockStepper stays within min and max', (tester) async {
    var value = 1;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => BlockStepper(
          value: value,
          min: 1,
          max: 3,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    final minus = find.byKey(const ValueKey('stepper.minus'));
    final plus = find.byKey(const ValueKey('stepper.plus'));

    await tester.tap(minus);
    await tester.pump();
    expect(value, 1); // already at min

    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    expect(value, 3); // stopped at max
    expect(find.text('3'), findsOneWidget);
    expect(tester.getSize(plus).height, greaterThanOrEqualTo(Sizes.target));
  });

  testWidgets('SegmentedChoice selects one option', (tester) async {
    String? chosen = 'cash';
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SegmentedChoice<String>(
          options: const [
            ChoiceOption('cash', 'Cash'),
            ChoiceOption('paybill', 'Paybill', caption: 'M-Pesa code needed'),
          ],
          selected: chosen,
          onChanged: (v) => setState(() => chosen = v),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('choice.paybill')));
    await tester.pump();
    expect(chosen, 'paybill');
    // Selection is shown by a filled radio, not colour alone.
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
  });

  testWidgets('every bed status has its own label and spoken text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      Column(
        children: [
          for (final status in BedTileStatus.values)
            BedStatusTile(
              label: 'A',
              title: 'Deluxe · KES 700',
              subtitle: 'line two',
              status: status,
            ),
        ],
      ),
    );
    for (final status in BedTileStatus.values) {
      expect(find.text(status.badge), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Bed A, Deluxe · KES 700. ${status.spoken}. line two',
        ),
        findsOneWidget,
      );
    }
    handle.dispose();
  });

  testWidgets('buttons ignore taps while busy and are 44px or taller', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      Column(
        children: [
          AppButton.primary(
            key: const ValueKey('busy'),
            label: 'Save',
            busy: true,
            onPressed: () => taps++,
          ),
          AppButton.secondary(
            key: const ValueKey('idle'),
            label: 'Cancel',
            onPressed: () => taps++,
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('busy')));
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('idle')));
    expect(taps, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('idle'))).height,
      greaterThanOrEqualTo(Sizes.target),
    );
  });

  testWidgets('notes carry an icon per tone, not just a colour', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        children: [
          Note.info('Info'),
          Note.warning('Warning'),
          Note.error('Error'),
          StatusBadge('CLOSED · REPAIRS', tone: BadgeTone.warning),
        ],
      ),
    );
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('CLOSED · REPAIRS'), findsOneWidget);
  });
}
