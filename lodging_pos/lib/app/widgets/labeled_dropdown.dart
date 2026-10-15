import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One entry of a [LabeledDropdown].
class DropdownOption<T> {
  const DropdownOption(this.value, this.label, {this.enabled = true});
  final T value;
  final String label;

  /// A disabled option is shown (e.g. the current, now-closed category) but
  /// can't be chosen.
  final bool enabled;
}

/// A select with its label above (13/700), styled like [LabeledField].
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    this.errorText,
  });

  final String label;
  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final Key? fieldKey;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.fieldLabel),
        const SizedBox(height: Space.x6),
        DropdownButtonFormField<T>(
          // Rebuild when the value changes from outside.
          key: fieldKey ?? ValueKey('$label:$value'),
          initialValue: value,
          isExpanded: true,
          style: t.body,
          borderRadius: BorderRadius.circular(Radii.control),
          dropdownColor: c.white,
          icon: Icon(Icons.expand_more_rounded, color: c.inkSoft),
          decoration: InputDecoration(errorText: errorText),
          items: [
            for (final option in options)
              DropdownMenuItem<T>(
                value: option.value,
                enabled: option.enabled,
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: option.enabled
                      ? t.body
                      : t.body.copyWith(color: c.disabled),
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged!(v);
                },
        ),
      ],
    );
  }
}
