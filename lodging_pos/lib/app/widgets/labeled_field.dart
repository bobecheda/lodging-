import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// A text input with its label above (13/700), per the spec. White, 1px
/// field border, 1.5px marine when focused, radius 10.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.errorText,
    this.helperText,
    this.hintText,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.textStyle,
    this.prefix,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;

  /// Key for the inner TextField (tests and focus).
  final Key? fieldKey;
  final String? errorText;

  /// Shown under the field when there is no error, e.g. an allowed range.
  final String? helperText;
  final String? hintText;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? textStyle;
  final Widget? prefix;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.fieldLabel),
        const SizedBox(height: Space.x6),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          style: textStyle ?? t.body,
          decoration: InputDecoration(
            errorText: errorText,
            helperText: helperText,
            hintText: hintText,
            prefixIcon: prefix,
            prefixIconConstraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }
}
