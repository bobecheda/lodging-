import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/theme/theme.dart';

/// The v2 motion tokens (docs/design-system.md, "Motion"), and reduced
/// motion: with animations off, every duration and offset is zero.
void main() {
  Future<LodgingMotion> motionWith(
    WidgetTester tester, {
    required bool disableAnimations,
  }) async {
    late LodgingMotion motion;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLodgingTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) {
              motion = LodgingMotion.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return motion;
  }

  testWidgets('the brief’s durations, easings and offsets', (tester) async {
    final m = await motionWith(tester, disableAnimations: false);
    expect(m.reduced, isFalse);
    expect(m.tabIndicator.duration, const Duration(milliseconds: 200));
    expect(m.tabIndicator.curve, Curves.easeOut);
    expect(m.tabOut.duration, const Duration(milliseconds: 120));
    expect(m.tabOut.curve, Curves.easeIn);
    expect(m.tabIn.duration, const Duration(milliseconds: 180));
    expect(m.tabIn.curve, Curves.easeOut);
    expect(m.tabRise, 8);
    expect(m.flowIn.duration, const Duration(milliseconds: 250));
    expect(m.flowBack.duration, const Duration(milliseconds: 200));
    expect(m.flowBack.curve, Curves.easeIn);
    expect(m.flowSlide, 16);
    expect(m.menuOpen.duration, const Duration(milliseconds: 150));
    expect(m.menuClose.duration, const Duration(milliseconds: 120));
    expect(m.menuDrop, 4);
    expect(m.panel.duration, const Duration(milliseconds: 220));
    expect(m.scrim.duration, const Duration(milliseconds: 150));
    expect(m.count.duration, const Duration(milliseconds: 150));
  });

  testWidgets('reduced motion: instant, no movement', (tester) async {
    final m = await motionWith(tester, disableAnimations: true);
    expect(m.reduced, isTrue);
    for (final step in [
      m.tabIndicator,
      m.tabOut,
      m.tabIn,
      m.flowIn,
      m.flowBack,
      m.menuOpen,
      m.menuClose,
      m.panel,
      m.scrim,
      m.count,
    ]) {
      expect(step.duration, Duration.zero);
    }
    expect([m.tabRise, m.flowSlide, m.menuDrop], everyElement(0));
  });
}
