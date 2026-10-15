import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum _Tone { info, warning, error }

/// A short message in a tinted box with an icon (spec, "Info note /
/// Warning chip / Error"): info = marineTint, warning = butter, error =
/// redTint. The icon differs per tone, so meaning isn't colour alone.
class Note extends StatelessWidget {
  const Note.info(this.message, {super.key, this.title}) : _tone = _Tone.info;
  const Note.warning(this.message, {super.key, this.title})
    : _tone = _Tone.warning;
  const Note.error(this.message, {super.key, this.title}) : _tone = _Tone.error;

  final String message;
  final String? title;
  final _Tone _tone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (Color bg, Color fg, Color? border, IconData icon) = switch (_tone) {
      _Tone.info => (c.marineTint, c.marine, null, Icons.info_outline_rounded),
      _Tone.warning => (
        c.butter,
        c.butterText,
        null,
        Icons.warning_amber_rounded,
      ),
      _Tone.error => (
        c.redTint,
        c.redText,
        c.redBorder,
        Icons.error_outline_rounded,
      ),
    };
    return Semantics(
      liveRegion: _tone == _Tone.error,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x14,
          vertical: Space.x12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.control),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: Space.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(title!, style: t.bodyStrong.copyWith(color: fg)),
                  Text(
                    message,
                    style: (title == null ? t.bodyStrong : t.body).copyWith(
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BadgeTone { neutral, active, warning, disabled }

/// A small caps status label, e.g. ACTIVE, CLOSED · REPAIRS, MUST SET
/// PASSWORD, DISABLED. Pass the text in capitals.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.tone = BadgeTone.neutral});

  final String text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (Color? bg, Color fg) = switch (tone) {
      BadgeTone.neutral => (c.marineTint, c.marine),
      BadgeTone.active => (null, c.marine),
      BadgeTone.warning => (c.butter, c.butterText),
      BadgeTone.disabled => (c.lineSoft, c.muted),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: bg == null ? 0 : Space.x8,
        vertical: Space.x4,
      ),
      decoration: bg == null
          ? null
          : BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.badge),
            ),
      child: Text(text, style: t.capsLabel.copyWith(color: fg)),
    );
  }
}
