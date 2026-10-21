import 'package:flutter/material.dart';

import 'lodging_colors.dart';
import 'lodging_type.dart';
import 'spacing.dart';

export 'lodging_colors.dart';
export 'lodging_type.dart';
export 'spacing.dart';
export 'wordmark_style.dart';

/// The app theme: light only, hand-written ColorScheme (no fromSeed), no
/// shadows or gradients (docs/design.md).
ThemeData buildLodgingTheme() {
  const c = LodgingColors.light;
  final type = LodgingType.from(c);

  final scheme = ColorScheme(
    brightness: Brightness.light,
    primary: c.marine,
    onPrimary: c.white,
    primaryContainer: c.marineTint,
    onPrimaryContainer: c.marine,
    secondary: c.marine600,
    onSecondary: c.white,
    secondaryContainer: c.marineTintStrong,
    onSecondaryContainer: c.marine,
    tertiary: c.butter,
    onTertiary: c.butterText,
    error: c.redDark,
    onError: c.white,
    errorContainer: c.redTint,
    onErrorContainer: c.redText,
    surface: c.white,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.white,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.lineSoft,
    surfaceContainerHighest: c.line,
    outline: c.fieldBorder,
    outlineVariant: c.line,
    shadow: c.ink.withValues(alpha: 0),
    scrim: c.scrim,
    inverseSurface: c.marine,
    onInverseSurface: c.white,
    inversePrimary: c.marineTint,
    surfaceTint: c.white.withValues(alpha: 0),
  );

  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.control),
    borderSide: BorderSide(color: color, width: width),
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: manrope,
    scaffoldBackgroundColor: c.surface,
    extensions: [c, type],
    textTheme: TextTheme(
      headlineSmall: type.pageTitle,
      titleLarge: type.pageTitle,
      titleMedium: type.sectionTitle,
      titleSmall: type.bodyStrong,
      bodyLarge: type.body,
      bodyMedium: type.body,
      bodySmall: type.small,
      labelLarge: type.button,
      labelMedium: type.fieldLabel,
      labelSmall: type.capsLabel,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: c.marine,
            foregroundColor: c.white,
            disabledBackgroundColor: c.line,
            disabledForegroundColor: c.disabled,
            minimumSize: const Size(Sizes.target, Sizes.target),
            padding: const EdgeInsets.symmetric(horizontal: Space.x20),
            shape: controlShape,
            textStyle: type.button,
            elevation: 0,
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              c.marine600.withValues(alpha: 0.4),
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.white,
        foregroundColor: c.marine,
        disabledForegroundColor: c.disabled,
        minimumSize: const Size(Sizes.target, Sizes.target),
        padding: const EdgeInsets.symmetric(horizontal: Space.x20),
        shape: controlShape,
        side: BorderSide(color: c.fieldBorder),
        textStyle: type.button.copyWith(color: c.marine),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.marine,
        minimumSize: const Size(Sizes.targetCompact, Sizes.targetCompact),
        textStyle: type.bodyStrong,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.white,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.x14,
        vertical: Space.x14,
      ),
      hintStyle: type.body.copyWith(color: c.disabled),
      errorStyle: type.small.copyWith(color: c.redDark),
      helperStyle: type.small,
      border: border(c.fieldBorder, Sizes.borderThin),
      enabledBorder: border(c.fieldBorder, Sizes.borderThin),
      focusedBorder: border(c.marine, Sizes.borderStrong),
      errorBorder: border(c.redDark, Sizes.borderThin),
      focusedErrorBorder: border(c.redDark, Sizes.borderStrong),
      disabledBorder: border(c.line, Sizes.borderThin),
    ),
    cardTheme: CardThemeData(
      color: c.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: c.line),
      ),
      titleTextStyle: type.sectionTitle,
      contentTextStyle: type.body,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.marine),
    iconTheme: IconThemeData(color: c.inkSoft, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(Radii.badge),
      ),
      textStyle: type.small.copyWith(color: c.white),
    ),
  );
}
