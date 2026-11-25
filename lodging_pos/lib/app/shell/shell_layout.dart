/// The desk shell's pure rules (docs/design-system.md, "Desk navigation"
/// and "Layout and responsive"): breakpoints, how wide a top tab is, when
/// the tabs no longer fit and collapse into the menu, which tab a route
/// belongs to, and the avatar's initials. No Flutter imports.
library;

/// Breakpoints: narrow < 768, medium 768–1279, wide ≥ 1280.
enum DeskWidth { narrow, medium, wide }

DeskWidth deskWidthOf(double width) => width < 768
    ? DeskWidth.narrow
    : width < 1280
    ? DeskWidth.medium
    : DeskWidth.wide;

/// The top tab's insides (Figma `v2/Top tab`): 12 px padding each side, an
/// 18 px icon, 8 px gaps, then an optional count badge and a 16 px chevron
/// for a menu tab.
const tabPadding = 12.0;
const tabIconSize = 18.0;
const tabGap = 8.0;
const tabChevron = 16.0;

/// Between two tabs.
const tabSpacing = 4.0;

/// A tab's width from its label's width, its badge's width (0: none) and
/// whether it opens a menu.
double topTabWidth({
  required double labelWidth,
  double badgeWidth = 0,
  bool menu = false,
}) =>
    tabPadding +
    tabIconSize +
    tabGap +
    labelWidth +
    (badgeWidth > 0 ? tabGap + badgeWidth : 0) +
    (menu ? tabGap + tabChevron : 0) +
    tabPadding;

/// Whether tabs this wide fit in a bar [barWidth] wide between its left
/// part ([leading]: padding, wordmark, gap) and its right part
/// ([trailing]: status, user, Lock, padding). The tabs collapse into the
/// menu whenever they don't (brief, "Tabs collapse into the menu button
/// whenever they don't fit").
bool tabsFit({
  required double barWidth,
  required double leading,
  required double trailing,
  required List<double> tabWidths,
}) {
  if (tabWidths.isEmpty) return true;
  final tabs =
      tabWidths.fold<double>(0, (sum, w) => sum + w) +
      tabSpacing * (tabWidths.length - 1);
  return leading + tabs + trailing <= barWidth;
}

/// How the top bar fits its width (brief, "Bed board — fixes after the
/// first build"): labels are never cut. When space runs short the user's
/// name hides first, then the tabs fold into the menu button (the name
/// stays hidden then, as in the 768 design).
enum BarLayout { full, noName, folded }

/// [leading]: padding, wordmark and gap; [trailing]: status, user block
/// (with its name, [nameWidth] of it) and Lock, with padding.
BarLayout barLayout({
  required double barWidth,
  required double leading,
  required List<double> tabWidths,
  required double trailing,
  required double nameWidth,
}) {
  bool fits(double right) => tabsFit(
    barWidth: barWidth,
    leading: leading,
    trailing: right,
    tabWidths: tabWidths,
  );
  if (fits(trailing)) return BarLayout.full;
  if (fits(trailing - nameWidth)) return BarLayout.noName;
  return BarLayout.folded;
}

/// A measured text width, rounded up to the next whole pixel: text drawn on
/// a scaled display (125%, 150%) can need the fraction, and a label that
/// gets less than it needs is cut.
double measuredWidth(double width) => width.ceilToDouble();

/// The nav route a location belongs to: itself, the route it sits under
/// (`/cash/count` → `/cash`, `/owner/refund` → `/owner`), or a flow's home
/// (`/check-in` → the bed board, given as [flows]). Null when none of
/// [routes] matches.
String? activeRouteFor(
  String location,
  Iterable<String> routes, {
  Map<String, String> flows = const {},
}) {
  final path = Uri.parse(location).path;
  if (routes.contains(path)) return path;
  if (flows[path] case final home? when routes.contains(home)) return home;
  String? best;
  for (final r in routes) {
    if (path.startsWith('$r/') && (best == null || r.length > best.length)) {
      best = r;
    }
  }
  return best;
}

/// "AK" for Akinyi, "GS" for Grace Supervisor: the first letters of the
/// first two words, or the first two letters of a single name.
String initialsOf(String fullName) {
  final words = fullName.trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.single;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}
