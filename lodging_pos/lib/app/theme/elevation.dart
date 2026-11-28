import 'package:flutter/painting.dart';

import 'lodging_colors.dart';

/// The few shadows the app draws (story/ui-floating-nav): soft, ink at
/// 8% or less, never on cards. Menus and the drawer keep their own (ink
/// 8%, 16 blur).
abstract final class LodgingShadows {
  /// The floating top bar: lifts it off the page, with its 1 px line
  /// border.
  static List<BoxShadow> floatingBar(LodgingColors c) => [
    BoxShadow(
      color: c.ink.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
