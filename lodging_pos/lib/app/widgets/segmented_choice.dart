import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One option of a [SegmentedChoice].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, {this.icon, this.caption});
  final T value;
  final String label;
  final IconData? icon;

  /// Optional second line, e.g. "M-Pesa code needed".
  final String? caption;
}

/// Equal-width radio cards (e.g. Cash / Paybill). The selected card has a
/// 1.5px marine border, marineTintStrong fill and marine 800 text, and a
/// filled radio mark, so selection never relies on colour alone.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ChoiceOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, option) in options.indexed) ...[
        if (i > 0) const SizedBox(width: Space.x12),
        Expanded(child: _Card(option, option.value == selected, onChanged)),
      ],
    ],
  );
}

class _Card<T> extends StatelessWidget {
  const _Card(this.option, this.isSelected, this.onChanged);

  final ChoiceOption<T> option;
  final bool isSelected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final textColor = isSelected ? c.marine : c.ink;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      button: true,
      label: option.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('choice.${option.value}'),
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onChanged == null ? null : () => onChanged!(option.value),
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.targetLarge),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x14,
            vertical: Space.x10,
          ),
          decoration: BoxDecoration(
            color: isSelected ? c.marineTintStrong : c.white,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: isSelected ? c.marine : c.fieldBorder,
              width: isSelected ? Sizes.borderStrong : Sizes.borderThin,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSelected ? c.marine : c.muted,
              ),
              const SizedBox(width: Space.x10),
              if (option.icon != null) ...[
                Icon(option.icon, size: 20, color: textColor),
                const SizedBox(width: Space.x8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: t.bodyStrong.copyWith(
                        color: textColor,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                    if (option.caption != null)
                      Text(option.caption!, style: t.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
