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
    this.onChanged,
    this.inputFormatters,
    this.textStyle,
    this.prefix,
    this.suffixText,
    this.autofillHints,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Shown above the field; null in a table row whose column says it (give
  /// [semanticLabel] instead, so screen readers still name the field).
  final String? label;
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
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? textStyle;
  final Widget? prefix;

  /// A unit after the value, e.g. "minutes".
  final String? suffixText;
  final Iterable<String>? autofillHints;

  /// False shows the value read-only (greyed).
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: t.fieldLabel),
          const SizedBox(height: Space.x6),
        ],
        Semantics(
          label: label == null ? semanticLabel : null,
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            autofocus: autofocus,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            inputFormatters: inputFormatters,
            autofillHints: autofillHints,
            style: textStyle ?? t.body,
            decoration: InputDecoration(
              errorText: errorText,
              helperText: helperText,
              helperMaxLines: 4,
              hintText: hintText,
              suffixText: suffixText,
              suffixStyle: t.body.copyWith(
                color: LodgingColors.of(context).muted,
              ),
              prefixIcon: prefix,
              prefixIconConstraints: const BoxConstraints(),
            ),
          ),
        ),
      ],
    );
  }
}
