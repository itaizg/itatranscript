import 'package:material_ui/material_ui.dart';

import '../models/caption_segment.dart';

final RegExp _hebrew = RegExp('[֐-׿]');
final RegExp _latin = RegExp('[A-Za-z]');

/// Direction of a segment: Hebrew right-to-left, everything else left-to-right (FR-003).
/// A line that mixes both follows whichever script comes first.
TextDirection directionFor(CaptionSegment s) {
  final int he = s.text.indexOf(_hebrew);
  final int en = s.text.indexOf(_latin);
  if (he < 0) {
    return TextDirection.ltr;
  }
  if (en < 0 || he < en) {
    return TextDirection.rtl;
  }
  return TextDirection.ltr;
}

/// The text to show for a segment.
String displayText(CaptionSegment s) =>
    s.isUnrecognized ? '[unrecognized]' : s.text;

/// Sizes for the caption lines, newest first (FR-007): the newest is the largest.
double fontSizeFor({required int ageIndex, required double scale}) {
  const double base = 22;
  const double newest = 34;
  return (ageIndex == 0
          ? newest
          : (base - (ageIndex - 1).clamp(0, 6)).toDouble()) *
      scale /
      1.6;
}

/// Colors and style for one caption line.
TextStyle styleFor(
  CaptionSegment s, {
  required int ageIndex,
  required double scale,
}) {
  final bool provisional = s.status == SegmentStatus.provisional;
  final double fade = ageIndex == 0
      ? 1
      : (1 - 0.12 * ageIndex).clamp(0.45, 1.0);
  final Color color = s.isUnrecognized
      ? const Color(0xFF8A8A8A)
      : provisional
      ? const Color(0xFFA6A6A6)
      : Color.fromRGBO(255, 255, 255, fade);
  return TextStyle(
    fontSize: fontSizeFor(ageIndex: ageIndex, scale: scale),
    color: color,
    fontStyle: provisional ? FontStyle.italic : FontStyle.normal,
    height: 1.25,
  );
}
