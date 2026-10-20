import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'wordmark.dart';

/// Sign-in style screens (sign in, lock, change password, first-run setup):
/// a marine brand panel on the left and the form on the right (artboard
/// "Sign in and screen lock").
class SplitGateLayout extends ConsumerWidget {
  const SplitGateLayout({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.above,
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Shown above the title, e.g. the "Screen locked" chip.
  final Widget? above;
  final List<Widget> children;

  /// Small centred text under the form.
  final String? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = (constraints.maxWidth * 0.31).clamp(320.0, 480.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: panelWidth,
                color: c.marine,
                padding: const EdgeInsets.all(Space.x32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LodgingWordmark(size: WordmarkSize.panel),
                    const Spacer(),
                    Text(
                      'Front desk',
                      style: t.heroTitle.copyWith(color: c.white),
                    ),
                    const SizedBox(height: Space.x12),
                    Text(
                      'Every bed, guest and shilling in one place. '
                      'Works with or without internet.',
                      style: t.body.copyWith(color: c.navMuted),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          width: Space.x8,
                          height: Space.x8,
                          decoration: BoxDecoration(
                            color: c.butter,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Space.x8),
                        Expanded(
                          child: Text(
                            'Sign-in works without internet',
                            style: t.smallStrong.copyWith(color: c.navText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x32,
                      vertical: Space.x32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Sizes.formMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (above != null) ...[
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: above,
                            ),
                            const SizedBox(height: Space.x16),
                          ],
                          Semantics(
                            header: true,
                            child: Text(title, style: t.cardTitle),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: Space.x8),
                            Text(
                              subtitle!,
                              style: t.body.copyWith(color: c.muted),
                            ),
                          ],
                          const SizedBox(height: Space.x24),
                          ...children,
                          if (footer != null) ...[
                            const SizedBox(height: Space.x16),
                            Text(
                              footer!,
                              textAlign: TextAlign.center,
                              style: t.small,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Vertical gap between form fields.
const formGap = SizedBox(height: Space.x16);
