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
  static const tab = 8.0; // top tabs, menu and drawer rows
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

  /// The desk's top bar (v2 PR 3): 64 high, its tabs 44 high, a 3 px
  /// indicator under the active one.
  static const topBar = 64.0;
  static const tabIndicator = 3.0;
  static const tabIcon = 18.0;

  /// The user's initials in the top bar and the drawer.
  static const avatar = 36.0;

  /// Menus (Setup ▾, More ▾, the user menu): 240 wide, 44 px rows, 20 px
  /// icons.
  static const menuWidth = 240.0;
  static const menuIcon = 20.0;

  /// The menu drawer when the tabs don't fit: 304 wide, 48 px rows.
  static const drawerWidth = 304.0;
  static const drawerRow = 48.0;

  /// The keyboard focus ring: 2 px marine, 2 px outside the control.
  static const focusRing = 2.0;
  static const focusGap = 2.0;

  /// Page content is capped at this width on very wide screens; the top
  /// bar stays full width.
  static const contentMax = 1280.0;
  static const bedPanelWidth = 440.0;
  static const borderThin = 1.0;
  static const borderStrong = 1.5;

  /// Readable width for forms on gate screens.
  static const formMaxWidth = 420.0;
}
