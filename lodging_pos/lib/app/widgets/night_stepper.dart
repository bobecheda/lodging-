import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// − / value / + with 44×44 buttons and the value in mono 22 (spec,
/// "Stepper (nights)"). The buttons disable at [min] and [max].
class NightStepper extends StatelessWidget {
  const NightStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.unit = 'nights',
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// Read out with the value, e.g. "2 nights".
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    Widget button(IconData icon, String label, int? next, Key key) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: Sizes.target,
        child: OutlinedButton(
          key: key,
          onPressed: next == null || onChanged == null
              ? null
              : () => onChanged!(next),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(Sizes.target),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.remove_rounded,
          'Fewer $unit',
          value > min ? value - 1 : null,
          const ValueKey('stepper.minus'),
        ),
        Semantics(
          value: '$value $unit',
          excludeSemantics: true,
          child: SizedBox(
            width: 64,
            child: Text(
              '$value',
              key: const ValueKey('stepper.value'),
              textAlign: TextAlign.center,
              style: t.stepperValue.copyWith(color: c.ink),
            ),
          ),
        ),
        button(
          Icons.add_rounded,
          'More $unit',
          value < max ? value + 1 : null,
          const ValueKey('stepper.plus'),
        ),
      ],
    );
  }
}
