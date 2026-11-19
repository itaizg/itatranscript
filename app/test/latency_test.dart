import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/fake_engine.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/session/latency.dart';

import 'support.dart';

void main() {
  test('latency-basic matches the numbers in latency-basic.expected.json', () {
    final events = parseEventLog(
      readShared('fixtures/latency-basic.events.jsonl'),
    );
    final spans = <SpeechSpan>[
      for (final Object? s in asList(
        asMap(readSharedJson('fixtures/latency-basic.spans.json'))['spans'],
      ))
        SpeechSpan(
          onsetMs: asMap(s)['onset_ms']! as int,
          offsetMs: asMap(s)['offset_ms']! as int,
        ),
    ];
    final Map<String, Object?> expected = asMap(
      readSharedJson('fixtures/latency-basic.expected.json'),
    );
    final Map<String, Object?> prov = asMap(expected['provisional_ms']);
    final Map<String, Object?> fin = asMap(expected['final_ms']);
    final stats = computeLatency(events, spans, <int>[50, 90]);
    expect(stats.provisionalMs, prov['values']);
    expect(stats.finalMs, fin['values']);
    expect(stats.provisionalPct, <int, double>{
      50: (prov['p50']! as num).toDouble(),
      90: (prov['p90']! as num).toDouble(),
    });
    expect(stats.finalPct, <int, double>{
      50: (fin['p50']! as num).toDouble(),
      90: (fin['p90']! as num).toDouble(),
    });
  });

  test('no values gives NaN percentiles', () {
    expect(percentile(<int>[], 50).isNaN, isTrue);
  });
}
