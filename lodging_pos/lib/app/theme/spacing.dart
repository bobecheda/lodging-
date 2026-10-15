/// Spacing, radii and sizes (docs/design.md, "Shape and spacing").
abstract final class Space {
  static const x4 = 4.0;
  static const x6 = 6.0;
  static const x8 = 8.0;
  static const x10 = 10.0;
  static const x12 = 12.0;
  static const x14 = 14.0;
  static const x16 = 16.0;
  static const x18 = 18.0;
  static const x20 = 20.0;
  static const x24 = 24.0;
  static const x28 = 28.0;
  static const x32 = 32.0;
}

abstract final class Radii {
  static const card = 12.0;
  static const control = 10.0; // inputs and buttons
  static const tile = 8.0; // bed tiles
  static const badge = 6.0;
  static const pill = 999.0;
}

abstract final class Sizes {
  /// Buttons and inputs.
  static const target = 44.0;

  /// Primary actions on gate screens.
  static const targetLarge = 50.0;

  /// Compact table actions and filter chips.
  static const targetCompact = 36.0;

  static const sidebarWidth = 232.0;
  static const bedPanelWidth = 440.0;
  static const borderThin = 1.0;
  static const borderStrong = 1.5;

  /// Readable width for forms on gate screens.
  static const formMaxWidth = 420.0;
}
