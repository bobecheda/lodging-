import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum _Kind { primary, secondary, destructive, urgent }

/// A full-height action button that shows a spinner and ignores taps while
/// [busy]. Use the named constructors; colour carries meaning:
/// - [AppButton.primary]: marine fill, the main action.
/// - [AppButton.secondary]: white with a field border, marine text.
/// - [AppButton.destructive]: white with a red-text outline (e.g. Disable
///   user). Never red-filled.
/// - [AppButton.urgent]: red fill, for overstay actions only.
class AppButton extends StatelessWidget {
  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.large = false,
    this.compact = false,
  }) : _kind = _Kind.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.large = false,
    this.compact = false,
  }) : _kind = _Kind.secondary;

  const AppButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.large = false,
    this.compact = false,
  }) : _kind = _Kind.destructive;

  const AppButton.urgent({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.large = false,
    this.compact = false,
  }) : _kind = _Kind.urgent;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  /// 50px tall, for the main action of a gate screen.
  final bool large;

  /// 36px tall, for table rows and filter bars.
  final bool compact;
  final _Kind _kind;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final height = large
        ? Sizes.targetLarge
        : compact
        ? Sizes.targetCompact
        : Sizes.target;

    final (Color fill, Color text, Color? border) = switch (_kind) {
      _Kind.primary => (c.marine, c.white, null),
      _Kind.secondary => (c.white, c.marine, c.fieldBorder),
      _Kind.destructive => (c.white, c.redText, c.destructiveBorder),
      _Kind.urgent => (c.red, c.white, null),
    };
    final hover = switch (_kind) {
      _Kind.primary => c.marine600,
      _Kind.urgent => c.redDark,
      _ => c.marineTintStrong,
    };
    final textStyle = (compact ? t.bodyStrong : t.button).copyWith(color: text);

    final content = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: text),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: text),
                const SizedBox(width: Space.x8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.visible)),
            ],
          );

    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      label: busy ? '$label, working' : null,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(height, height)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: compact ? Space.x12 : Space.x20),
          ),
          textStyle: WidgetStatePropertyAll(textStyle),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.disabled) && !busy ? c.disabled : text,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled) && !busy) {
              return _kind == _Kind.primary || _kind == _Kind.urgent
                  ? c.line
                  : c.white;
            }
            if (s.contains(WidgetState.hovered) ||
                s.contains(WidgetState.pressed)) {
              return hover;
            }
            return fill;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.control),
              side: border == null
                  ? BorderSide.none
                  : BorderSide(color: border),
            ),
          ),
        ),
        child: content,
      ),
    );
  }
}
