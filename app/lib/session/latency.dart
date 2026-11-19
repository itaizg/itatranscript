import 'dart:math' as math;

import '../models/audio_frame.dart';
import '../models/engine_event.dart';

/// Per-utterance latencies and their percentiles (nearest-rank), as in research R-3.
class LatencyStats {
  /// Creates the stats.
  const LatencyStats({
    required this.provisionalMs,
    required this.finalMs,
    required this.provisionalPct,
    required this.finalPct,
  });

  /// First partial arrival minus VAD onset, per utterance.
  final List<int> provisionalMs;

  /// Last final arrival minus VAD offset, per utterance.
  final List<int> finalMs;

  /// Percentile → value for provisional latency (NaN when there are no values).
  final Map<int, double> provisionalPct;

  /// Percentile → value for final latency (NaN when there are no values).
  final Map<int, double> finalPct;
}

/// Nearest-rank percentile; NaN when [values] is empty.
double percentile(List<int> values, int pct) {
  if (values.isEmpty) {
    return double.nan;
  }
  final List<int> sorted = List<int>.of(values)..sort();
  final int rank = math.max(1, (pct / 100 * sorted.length).ceil());
  return sorted[rank - 1].toDouble();
}

/// The shared latency definition: events are matched to a VAD utterance by arrival time, from
/// its onset up to the next utterance's onset.
LatencyStats computeLatency(
  List<EngineEvent> events,
  List<SpeechSpan> spans,
  List<int> percentiles,
) {
  final List<SpeechSpan> ordered = List<SpeechSpan>.of(spans)
    ..sort((SpeechSpan a, SpeechSpan b) => a.onsetMs.compareTo(b.onsetMs));
  final List<int> ttp = <int>[];
  final List<int> ttf = <int>[];
  for (int i = 0; i < ordered.length; i++) {
    final SpeechSpan span = ordered[i];
    final int end = i + 1 < ordered.length ? ordered[i + 1].onsetMs : 1 << 62;
    final List<EngineEvent> window = events
        .where((EngineEvent e) => e.tMs >= span.onsetMs && e.tMs < end)
        .toList();
    final List<int> partials = window
        .whereType<PartialEvent>()
        .map((PartialEvent e) => e.tMs)
        .toList();
    final List<int> finals = window
        .whereType<FinalEvent>()
        .map((FinalEvent e) => e.tMs)
        .toList();
    if (partials.isNotEmpty) {
      ttp.add(partials.reduce(math.min) - span.onsetMs);
    }
    if (finals.isNotEmpty && span.offsetMs != null) {
      ttf.add(finals.reduce(math.max) - span.offsetMs!);
    }
  }
  return LatencyStats(
    provisionalMs: List<int>.unmodifiable(ttp),
    finalMs: List<int>.unmodifiable(ttf),
    provisionalPct: <int, double>{
      for (final int p in percentiles) p: percentile(ttp, p),
    },
    finalPct: <int, double>{
      for (final int p in percentiles) p: percentile(ttf, p),
    },
  );
}
