import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// − / value / + with 44×44 buttons and the value in mono 22 (spec,
/// "Stepper (nights)"). The buttons disable at [min] and [max].
///
/// With [onTyped], the value is also a text box (digits only): every edit
/// goes to [onTyped] as typed, for the caller to parse and check, and the
/// buttons step from the last good [value].
class NightStepper extends StatefulWidget {
  const NightStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.unit = 'nights',
    this.onTyped,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// Read out with the value, e.g. "2 nights".
  final String unit;
  final ValueChanged<String>? onTyped;

  @override
  State<NightStepper> createState() => _NightStepperState();
}

class _NightStepperState extends State<NightStepper> {
  late final _text = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(NightStepper old) {
    super.didUpdateWidget(old);
    // A button (or the caller) moved the value: show it. Typing that isn't
    // a number yet leaves the value alone, so it isn't overwritten.
    if (old.value != widget.value && _text.text != '${widget.value}') {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _step(int next) {
    _text.text = '$next';
    widget.onChanged?.call(next);
    widget.onTyped?.call('$next');
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final value = widget.value;
    final enabled = widget.onChanged != null;

    Widget button(IconData icon, String label, int? next, Key key) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: Sizes.target,
        child: OutlinedButton(
          key: key,
          onPressed: next == null || !enabled ? null : () => _step(next),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(Sizes.target),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );

    final style = t.stepperValue.copyWith(color: c.ink);
    final Widget shown = widget.onTyped == null
        ? Semantics(
            value: '$value ${widget.unit}',
            excludeSemantics: true,
            child: Text(
              '$value',
              key: const ValueKey('stepper.value'),
              textAlign: TextAlign.center,
              style: style,
            ),
          )
        : TextField(
            key: const ValueKey('stepper.value'),
            controller: _text,
            enabled: enabled,
            textAlign: TextAlign.center,
            style: style,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: Space.x8),
              semanticCounterText: widget.unit,
            ),
            onChanged: widget.onTyped,
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.remove_rounded,
          'Fewer ${widget.unit}',
          value > widget.min ? value - 1 : null,
          const ValueKey('stepper.minus'),
        ),
        SizedBox(width: 64, child: shown),
        button(
          Icons.add_rounded,
          'More ${widget.unit}',
          value < widget.max ? value + 1 : null,
          const ValueKey('stepper.plus'),
        ),
      ],
    );
  }
}
