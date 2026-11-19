import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/fake_engine.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/session/latency.dart';
import 'package:itatranscript/session/session_stats.dart';

import 'support.dart';

const List<String> _secretTexts = <String>[
  'TOP-SECRET-PHRASE',
  'שלום-סודי',
  'api-key-123',
];

SessionStats _session({Random? random}) {
  final StatsRecorder r = StatsRecorder(
    startedAt: DateTime.utc(2026, 12, 1, 19, 2, 11),
    languageMode: 'auto',
    activeEngineId: 'google-stt-he',
    fallbackEngineId: 'apple-ondevice',
    pipelineSha256: 'abc',
    usdPerHour: 2,
    batteryStartPct: 92,
  );
  // Known caption text goes through the recorder; none of it may come out the other side.
  r.onEvent(
    const PartialEvent(
      tMs: 1400,
      segmentId: 's',
      text: 'TOP-SECRET-PHRASE',
      startMs: 0,
    ),
    1400,
  );
  r.onEvent(
    const FinalEvent(
      tMs: 4000,
      segmentId: 's',
      text: 'שלום-סודי',
      lang: 'he',
      startMs: 0,
      endMs: 1,
    ),
    4000,
  );
  r.onEvent(
    const ErrorEvent(
      tMs: 9000,
      code: 'network',
      message: 'api-key-123',
      retryable: true,
    ),
    9000,
  );
  r.onEvent(const UsageEvent(tMs: 9100, audioSecondsBilled: 1800), 9100);
  r.setSpans(const <SpeechSpan>[SpeechSpan(onsetMs: 1000, offsetMs: 3000)]);
  r.onSwitch(atMs: 20000, toFallback: true, switchMs: 1800);
  r.onInterruptionStart(30000);
  r.onInterruptionEnd(75000);
  r
    ..batteryEndPct = 61
    ..lockedS = 3100;
  return r.finish(
    sessionMs: 5420000,
    reason: EndReason.userStop,
    sessionId: StatsRecorder.newId(random),
  );
}

void main() {
  test(
    'the written line contains none of the caption text, and no key',
    () async {
      final Directory dir = Directory.systemTemp.createTempSync('stats_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final StatsStore store = StatsStore(File('${dir.path}/stats.jsonl'));
      await store.append(_session());
      final String line = File('${dir.path}/stats.jsonl').readAsStringSync();
      for (final String secret in _secretTexts) {
        expect(line, isNot(contains(secret)));
      }
      final Map<String, Object?> json = asMap(jsonDecode(line));
      expect(json['v'], 1);
      expect(json['end_reason'], 'user_stop');
      expect(json['billed_audio_s'], 1800);
      expect(json['est_cost_usd'], 1.0);
      expect(asList(json['errors']).single, <String, Object?>{
        'at_s': 9,
        'code': 'network',
      });
      expect(asList(json['interruptions']).single, <String, Object?>{
        'at_s': 30,
        'kind': 'mic_in_use',
        'dur_s': 45,
      });
      expect(asList(json['fallback_switches']).single, <String, Object?>{
        'at_s': 20,
        'to': 'fallback',
        'switch_ms': 1800,
      });
    },
  );

  test('latency fields equal latency.dart on the same events', () {
    final events = parseEventLog(
      readShared('fixtures/latency-basic.events.jsonl'),
    );
    final StatsRecorder r = StatsRecorder(
      startedAt: DateTime.utc(2026),
      languageMode: 'auto',
      activeEngineId: 'x',
      fallbackEngineId: null,
      pipelineSha256: '',
      usdPerHour: 0,
    );
    for (final e in events) {
      r.onEvent(e, e.tMs);
    }
    final Map<String, Object?> spansJson = asMap(
      readSharedJson('fixtures/latency-basic.spans.json'),
    );
    final List<SpeechSpan> spans = <SpeechSpan>[
      for (final Object? s in asList(spansJson['spans']))
        SpeechSpan(
          onsetMs: asMap(s)['onset_ms']! as int,
          offsetMs: asMap(s)['offset_ms']! as int,
        ),
    ];
    r.setSpans(spans);
    final SessionStats stats = r.finish(
      sessionMs: 1000,
      reason: EndReason.userStop,
      sessionId: 'x',
    );
    final LatencyStats expected = computeLatency(events, spans, <int>[50, 90]);
    expect(stats.provisional.p50, expected.provisionalPct[50]!.toInt());
    expect(stats.provisional.p90, expected.provisionalPct[90]!.toInt());
    expect(stats.finalLatency.p50, expected.finalPct[50]!.toInt());
    expect(stats.finalLatency.n, expected.finalMs.length);
    final Map<String, Object?> expectedJson = asMap(
      readSharedJson('fixtures/latency-basic.expected.json'),
    );
    expect(stats.provisional.p50, asMap(expectedJson['provisional_ms'])['p50']);
  });

  test('delete-one and delete-all work', () async {
    final Directory dir = Directory.systemTemp.createTempSync('stats_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final StatsStore store = StatsStore(File('${dir.path}/stats.jsonl'));
    final SessionStats a = _session(random: Random(1));
    final SessionStats b = _session(random: Random(2));
    await store.append(a);
    await store.append(b);
    expect(await store.readAll(), hasLength(2));
    await store.deleteOne(a.sessionId);
    final List<Map<String, Object?>> left = await store.readAll();
    expect(left.single['session_id'], b.sessionId);
    await store.deleteAll();
    expect(await store.readAll(), isEmpty);
  });

  test('session ids are random 32-hex strings', () {
    expect(StatsRecorder.newId(Random(7)), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      StatsRecorder.newId(Random(7)),
      isNot(StatsRecorder.newId(Random(8))),
    );
  });

  test(
    'an interruption with no start is ignored; a frame constant is sane',
    () {
      final StatsRecorder r = StatsRecorder(
        startedAt: DateTime.utc(2026),
        languageMode: 'en',
        activeEngineId: 'x',
        fallbackEngineId: null,
        pipelineSha256: '',
        usdPerHour: 0,
      )..onInterruptionEnd(5000);
      expect(
        r
            .finish(sessionMs: 0, reason: EndReason.error, sessionId: 's')
            .interruptions,
        isEmpty,
      );
      expect(kFrameMs, 20);
    },
  );
}
