import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/session/session_controller.dart';
import 'package:itatranscript/session/battery_watch.dart';
import 'package:itatranscript/session/cost_meter.dart';
import 'package:itatranscript/session/session_stats.dart';

import 'dart:io';
import 'dart:convert';

import 'fakes.dart';
import 'rig.dart';

void main() {
  test('idle → starting → live → ended', () async {
    final Rig r = Rig();
    await r.controller.start();
    expect(r.controller.snapshot.value.state, SessionState.starting);
    expect(r.audio.started, isTrue);
    await r.speak();
    expect(r.controller.snapshot.value.state, SessionState.live);
    expect(r.engines.single.received, isNotEmpty);
    await r.controller.stop();
    expect(r.controller.snapshot.value.state, SessionState.ended);
    expect(r.states, <SessionState>[
      SessionState.starting,
      SessionState.live,
      SessionState.ended,
    ]);
    expect(r.audio.started, isFalse);
  });

  test('engine events become captions in the snapshot', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single
      ..emit(
        const PartialEvent(
          tMs: 1,
          segmentId: 's1',
          text: 'hel',
          lang: 'en',
          startMs: 0,
        ),
      )
      ..emit(
        const FinalEvent(
          tMs: 2,
          segmentId: 's1',
          text: 'hello',
          lang: 'en',
          startMs: 0,
          endMs: 500,
        ),
      );
    await pumpEventQueue();
    final List<CaptionSegment> segs = r.controller.snapshot.value.segments;
    expect(segs.single.text, 'hello');
    expect(segs.single.status, SegmentStatus.finalized);
  });

  test('silence is never sent to the engine', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.hush();
    expect(r.engines.single.received, isEmpty);
    expect(r.controller.snapshot.value.state, SessionState.starting);
  });

  test('a language change applies at the next VAD pause via finish + reopen (R-14)', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.controller.setLanguageMode(LanguageMode.he);
    expect(r.engines, hasLength(1), reason: 'no reopen while speech is open');
    expect(r.engines.first.finished, isFalse);
    await r.hush();
    expect(r.engines.first.finished, isTrue);
    expect(r.engines, hasLength(2));
    expect(r.engines.last.openedWith, LanguageMode.he);
    expect(r.controller.snapshot.value.languageMode, LanguageMode.he);
  });

  test('a language change keeps the segments of the same session', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.first.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's1',
        text: 'one',
        lang: 'en',
        startMs: 0,
        endMs: 5,
      ),
    );
    await pumpEventQueue();
    r.controller.setLanguageMode(LanguageMode.he);
    await r.hush();
    r.engines.last.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's1',
        text: 'שתיים',
        lang: 'he',
        startMs: 0,
        endMs: 5,
      ),
    );
    await pumpEventQueue();
    expect(
      r.controller.snapshot.value.segments.map((CaptionSegment s) => s.text),
      <String>['one', 'שתיים'],
    );
  });

  test('an engine stream error becomes a visible error state, never stale text shown as live', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single
      ..emit(
        const FinalEvent(
          tMs: 1,
          segmentId: 's1',
          text: 'kept',
          lang: 'en',
          startMs: 0,
          endMs: 5,
        ),
      )
      ..emit(
        const PartialEvent(
          tMs: 2,
          segmentId: 's2',
          text: 'stale',
          lang: 'en',
          startMs: 6,
        ),
      );
    await pumpEventQueue();
    r.engines.single.out.addError(StateError('socket closed'));
    await pumpEventQueue();
    final SessionSnapshot s = r.controller.snapshot.value;
    expect(s.state, SessionState.ended);
    expect(s.errorMessage, isNotNull);
    expect(s.segments.map((CaptionSegment x) => x.text), <String>['kept']);
    expect(r.engines.single.cancelled, isTrue);
  });

  test('a non-retryable engine error ends the session visibly', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single.emit(
      const ErrorEvent(
        tMs: 1,
        code: 'auth',
        message: 'bad key',
        retryable: false,
      ),
    );
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.ended);
    expect(
      r.controller.snapshot.value.errorMessage,
      contains('Captions stopped'),
    );
  });

  test('the engine closing while live is an error, not silence', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.engines.single.emit(const ClosedEvent(tMs: 9));
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.ended);
  });

  test(
    'a failure to start (privacy gate, missing engine) is a visible error',
    () async {
      final Rig r = Rig(engine: 'does-not-exist');
      await r.controller.start();
      expect(r.controller.snapshot.value.state, SessionState.ended);
      expect(r.controller.snapshot.value.errorMessage, isNotNull);
    },
  );

  test('changing active_engine_id in Settings builds that adapter next session, with no code change', () async {
    final Rig first = Rig();
    await first.controller.start();
    expect(first.built, <String>['fake']);

    final Rig second = Rig();
    await second.store.save(
      (await second.store.load()).copyWith(activeEngineId: 'apple-ondevice'),
    );
    await second.controller.start();
    expect(second.built, <String>['apple_speech']);
  });

  test('snapshots are immutable', () async {
    final Rig r = Rig();
    await r.controller.start();
    expect(
      () => r.controller.snapshot.value.segments.add(
        const CaptionSegment(
          id: 'x',
          status: SegmentStatus.finalized,
          text: '',
          lang: 'en',
          startMs: 0,
          endMs: 0,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(r.controller.snapshot, isA<ValueListenable<SessionSnapshot>>());
  });

  test('a microphone interruption pauses with a reason and resumes afterwards (FR-022)', () async {
    final Rig r = Rig();
    await r.controller.start();
    await r.speak();
    r.audio.interrupt(paused: true, reason: 'phone call');
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.pausedMic);
    expect(r.controller.snapshot.value.pauseReason, 'phone call');
    r.audio.interrupt(paused: false);
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.live);
    expect(r.controller.snapshot.value.pauseReason, isNull);
  });

  test('a lost cloud engine moves to the fallback state and drops stale provisional text', () async {
    final Rig r = Rig(engine: 'google-stt-he', fallback: 'apple-ondevice');
    await r.controller.start();
    await r.speak();
    r.engines.first
      ..emit(
        const FinalEvent(
          tMs: 1,
          segmentId: 's1',
          text: 'kept',
          lang: 'en',
          startMs: 0,
          endMs: 400,
        ),
      )
      ..emit(
        const PartialEvent(
          tMs: 2,
          segmentId: 's2',
          text: 'stale',
          lang: 'en',
          startMs: 500,
        ),
      )
      ..emit(const HealthEvent(tMs: 3, state: 'lost', reason: 'socket'));
    await pumpEventQueue();
    final SessionSnapshot s = r.controller.snapshot.value;
    expect(s.state, SessionState.fallback);
    expect(s.segments.map((CaptionSegment x) => x.text), <String>['kept']);
    expect(r.engines, hasLength(2));
  });

  test('with no fallback, a lost cloud engine shows paused_offline', () async {
    final Rig r = Rig(engine: 'google-stt-he');
    await r.controller.start();
    await r.speak();
    r.engines.first.emit(
      const HealthEvent(tMs: 3, state: 'lost', reason: 'socket'),
    );
    await pumpEventQueue();
    expect(r.controller.snapshot.value.state, SessionState.pausedOffline);
  });

  test('stopping writes one stats line with no caption text', () async {
    final Directory dir = Directory.systemTemp.createTempSync('session_stats');
    addTearDown(() => dir.deleteSync(recursive: true));
    final StatsStore stats = StatsStore(File('${dir.path}/stats.jsonl'));
    final Rig r = Rig(
      extras: SessionExtras(stats: stats, pipelineSha256: 'abc'),
    );
    await r.controller.start();
    await r.speak();
    r.engines.single.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's1',
        text: 'PRIVATE WORDS',
        lang: 'en',
        startMs: 0,
        endMs: 5,
      ),
    );
    await pumpEventQueue();
    await r.controller.stop();
    final String written = File('${dir.path}/stats.jsonl').readAsStringSync();
    expect(const LineSplitter().convert(written), hasLength(1));
    expect(written, isNot(contains('PRIVATE WORDS')));
    expect(jsonDecode(written)['end_reason'], 'user_stop');
  });

  test(
    'billed audio feeds the cost meter and surfaces the warning level',
    () async {
      final CostMeter meter = CostMeter(
        capUsd: 1,
        store: MemoryKeyValueStore(),
      );
      final Rig r = Rig(
        engine: 'google-stt-he',
        extras: SessionExtras(
          costMeter: meter,
          wallClock: () => DateTime(2026, 11, 1),
        ),
      );
      await r.controller.start();
      await r.speak();
      r.engines.single.emit(const UsageEvent(tMs: 1, audioSecondsBilled: 3600));
      await pumpEventQueue();
      expect(
        meter.spentUsd(DateTime(2026, 11, 1)),
        r.profiles['google-stt-he']!.costUsdPerHour,
      );
    },
  );

  test('a low battery shows a banner flag with minutes left', () async {
    final _FakeBattery battery = _FakeBattery(
      const BatteryReading(percent: 50, charging: false),
    );
    final Rig r = Rig(extras: SessionExtras(battery: battery));
    await r.controller.start();
    await r.controller.checkBattery();
    expect(r.controller.snapshot.value.batteryLow, isFalse);
    battery.reading = const BatteryReading(percent: 8, charging: false);
    await r.controller.checkBattery();
    expect(r.controller.snapshot.value.batteryLow, isTrue);
  });
}

class _FakeBattery implements BatteryReader {
  _FakeBattery(this.reading);
  BatteryReading reading;

  @override
  Future<BatteryReading> read() async => reading;
}
