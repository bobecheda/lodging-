import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money/kes.dart';
import '../theme/theme.dart';
import 'labeled_field.dart';

/// Keeps whole-number input and groups thousands as the user types:
/// `2000` shows as `2,000`. Anything that isn't a digit is dropped.
class KesInputFormatter extends TextInputFormatter {
  const KesInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    // formatKes is the one place amounts are grouped; drop its prefix.
    final grouped = formatKes(int.parse(trimmed)).substring('KES '.length);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}

/// A KES amount: "KES" prefix in muted mono, the value in mono 600 (spec,
/// "Money input"). Read the value with `parseKes(controller.text)`.
class MoneyInput extends StatelessWidget {
  const MoneyInput({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.errorText,
    this.helperText,
    this.large = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? errorText;
  final String? helperText;

  /// The big variant (opening float, totals being entered).
  final bool large;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final valueStyle = large ? t.moneyLarge : t.monoStrong;
    return LabeledField(
      label: label,
      controller: controller,
      fieldKey: fieldKey,
      errorText: errorText,
      helperText: helperText,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: const [KesInputFormatter()],
      onSubmitted: onSubmitted,
      textStyle: valueStyle,
      hintText: '0',
      prefix: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: Space.x14,
          end: Space.x8,
        ),
        child: Text(
          'KES',
          style: (large ? t.monoStrong : t.mono).copyWith(color: c.muted),
        ),
      ),
    );
  }
}
