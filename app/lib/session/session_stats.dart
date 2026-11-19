import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/audio_frame.dart';
import '../models/engine_event.dart';
import 'latency.dart';

/// Why a session ended.
enum EndReason {
  /// The user pressed stop.
  userStop('user_stop'),

  /// iOS killed the app.
  osKilled('os_killed'),

  /// An error ended it.
  error('error'),

  /// The battery ran out or was low.
  battery('battery');

  const EndReason(this.wire);

  /// The value written to the stats file.
  final String wire;
}

/// One session's numbers (`contracts/session-stats.md`). There is no caption text and no audio
/// anywhere in this class, by construction.
class SessionStats {
  /// Creates the record.
  const SessionStats({
    required this.sessionId,
    required this.startedAt,
    required this.durationS,
    required this.languageMode,
    required this.activeEngineId,
    required this.fallbackEngineId,
    required this.pipelineSha256,
    required this.provisional,
    required this.finalLatency,
    required this.batteryStartPct,
    required this.batteryEndPct,
    required this.batteryWarnings,
    required this.lockedS,
    required this.fallbackSwitches,
    required this.interruptions,
    required this.errors,
    required this.billedAudioS,
    required this.estCostUsd,
    required this.endReason,
  });

  /// Random id.
  final String sessionId;

  /// UTC start time.
  final DateTime startedAt;

  /// Length in seconds.
  final int durationS;

  /// `auto`, `he` or `en`.
  final String languageMode;

  /// Engine used.
  final String activeEngineId;

  /// Fallback configured, if any.
  final String? fallbackEngineId;

  /// Hash of the pipeline config in force.
  final String pipelineSha256;

  /// Provisional latency percentiles and count.
  final LatencySummary provisional;

  /// Final latency percentiles and count.
  final LatencySummary finalLatency;

  /// Battery at start (percent), or null if unknown.
  final int? batteryStartPct;

  /// Battery at the end (percent), or null if unknown.
  final int? batteryEndPct;

  /// Battery-low warnings shown.
  final int batteryWarnings;

  /// Seconds spent with the screen locked.
  final int lockedS;

  /// Engine switches: `{at_s, to, switch_ms?}`.
  final List<Map<String, Object?>> fallbackSwitches;

  /// Microphone interruptions: `{at_s, kind, dur_s}`.
  final List<Map<String, Object?>> interruptions;

  /// Errors: `{at_s, code}`.
  final List<Map<String, Object?>> errors;

  /// Audio seconds billed.
  final double billedAudioS;

  /// Estimated cost in USD.
  final double estCostUsd;

  /// Why it ended.
  final EndReason endReason;

  /// The JSON object written as one line.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'session_id': sessionId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_s': durationS,
    'language_mode': languageMode,
    'active_engine_id': activeEngineId,
    'fallback_engine_id': ?fallbackEngineId,
    'pipeline_sha256': pipelineSha256,
    'provisional_ms': provisional.toJson(),
    'final_ms': finalLatency.toJson(),
    'battery_start_pct': ?batteryStartPct,
    'battery_end_pct': ?batteryEndPct,
    'battery_warnings': batteryWarnings,
    'locked_s': lockedS,
    'fallback_switches': fallbackSwitches,
    'interruptions': interruptions,
    'errors': errors,
    'billed_audio_s': billedAudioS,
    'est_cost_usd': estCostUsd,
    'end_reason': endReason.wire,
  };
}

/// p50, p90 and the number of utterances behind them.
class LatencySummary {
  /// Creates a summary; percentiles are null when there are no values.
  const LatencySummary({required this.p50, required this.p90, required this.n});

  /// Builds a summary from per-utterance values using the shared nearest-rank percentile.
  factory LatencySummary.of(List<int> values) => LatencySummary(
    p50: values.isEmpty ? null : percentile(values, 50).toInt(),
    p90: values.isEmpty ? null : percentile(values, 90).toInt(),
    n: values.length,
  );

  /// Median (ms).
  final int? p50;

  /// 90th percentile (ms).
  final int? p90;

  /// Number of utterances.
  final int n;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'p50': p50,
    'p90': p90,
    'n': n,
  };
}

/// Collects what happens in one session and produces its [SessionStats]. It never sees text:
/// events are reduced to arrival times and type before they are stored.
class StatsRecorder {
  /// Starts recording at [startedAt] (wall clock) for the given configuration.
  StatsRecorder({
    required this.startedAt,
    required this.languageMode,
    required this.activeEngineId,
    required this.fallbackEngineId,
    required this.pipelineSha256,
    required this.usdPerHour,
    this.batteryStartPct,
  });

  /// Wall-clock start.
  final DateTime startedAt;

  /// Language mode at start.
  final String languageMode;

  /// Active engine id.
  final String activeEngineId;

  /// Fallback engine id.
  final String? fallbackEngineId;

  /// Hash of `pipeline.yaml`.
  final String pipelineSha256;

  /// Price of the active engine.
  final double usdPerHour;

  /// Battery at start.
  final int? batteryStartPct;

  /// Battery at the end; set by the caller.
  int? batteryEndPct;

  /// Battery warnings shown; incremented by the caller.
  int batteryWarnings = 0;

  /// Seconds locked; set by the caller.
  int lockedS = 0;

  final List<_Arrival> _arrivals = <_Arrival>[];
  final List<SpeechSpan> _spans = <SpeechSpan>[];
  final List<Map<String, Object?>> _switches = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _interruptions = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _errors = <Map<String, Object?>>[];
  double _billed = 0;
  int? _interruptedAtS;

  /// Notes that an engine event arrived at [arrivalMs] (session time). The text is not kept.
  void onEvent(EngineEvent event, int arrivalMs) {
    switch (event) {
      case PartialEvent():
        _arrivals.add(_Arrival('partial', arrivalMs));
      case FinalEvent():
        _arrivals.add(_Arrival('final', arrivalMs));
      case UsageEvent():
        _billed += event.audioSecondsBilled;
      case ErrorEvent():
        _errors.add(<String, Object?>{
          'at_s': arrivalMs ~/ 1000,
          'code': event.code,
        });
      case SpeakerChangeEvent() || HealthEvent() || ClosedEvent():
        break;
    }
  }

  /// Replaces the VAD spans (used with arrival times for latency).
  void setSpans(List<SpeechSpan> spans) {
    _spans
      ..clear()
      ..addAll(spans);
  }

  /// Records an engine switch.
  void onSwitch({required int atMs, required bool toFallback, int? switchMs}) {
    _switches.add(<String, Object?>{
      'at_s': atMs ~/ 1000,
      'to': toFallback ? 'fallback' : 'active',
      'switch_ms': ?switchMs,
    });
  }

  /// Records the start of a microphone interruption at [atMs].
  void onInterruptionStart(int atMs) => _interruptedAtS = atMs ~/ 1000;

  /// Records the end of a microphone interruption at [atMs].
  void onInterruptionEnd(int atMs, {String kind = 'mic_in_use'}) {
    final int? start = _interruptedAtS;
    if (start == null) {
      return;
    }
    _interruptions.add(<String, Object?>{
      'at_s': start,
      'kind': kind,
      'dur_s': atMs ~/ 1000 - start,
    });
    _interruptedAtS = null;
  }

  /// Builds the record; [sessionMs] is the session length.
  SessionStats finish({
    required int sessionMs,
    required EndReason reason,
    required String sessionId,
  }) {
    final List<EngineEvent> arrivals = <EngineEvent>[
      for (final _Arrival a in _arrivals)
        if (a.kind == 'partial')
          PartialEvent(tMs: a.ms, segmentId: '', text: '', startMs: 0)
        else
          FinalEvent(
            tMs: a.ms,
            segmentId: '',
            text: '',
            lang: 'en',
            startMs: 0,
            endMs: 0,
          ),
    ];
    final LatencyStats latency = computeLatency(arrivals, _spans, const <int>[
      50,
      90,
    ]);
    return SessionStats(
      sessionId: sessionId,
      startedAt: startedAt,
      durationS: sessionMs ~/ 1000,
      languageMode: languageMode,
      activeEngineId: activeEngineId,
      fallbackEngineId: fallbackEngineId,
      pipelineSha256: pipelineSha256,
      provisional: LatencySummary.of(latency.provisionalMs),
      finalLatency: LatencySummary.of(latency.finalMs),
      batteryStartPct: batteryStartPct,
      batteryEndPct: batteryEndPct,
      batteryWarnings: batteryWarnings,
      lockedS: lockedS,
      fallbackSwitches: List<Map<String, Object?>>.unmodifiable(_switches),
      interruptions: List<Map<String, Object?>>.unmodifiable(_interruptions),
      errors: List<Map<String, Object?>>.unmodifiable(_errors),
      billedAudioS: _billed,
      estCostUsd: _billed / 3600 * usdPerHour,
      endReason: reason,
    );
  }

  /// A random 32-hex-digit session id.
  static String newId([math.Random? random]) {
    final math.Random r = random ?? math.Random.secure();
    return List<String>.generate(
      16,
      (int _) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

class _Arrival {
  const _Arrival(this.kind, this.ms);
  final String kind;
  final int ms;
}

/// The stats file: one JSON object per line, on the device only. The user can delete one entry or all.
class StatsStore {
  /// Creates a store over [file] (`stats.jsonl` in the documents directory).
  const StatsStore(this.file);

  /// The backing file.
  final File file;

  /// Appends one session.
  Future<void> append(SessionStats stats) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(stats.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// All stored records, oldest first.
  Future<List<Map<String, Object?>>> readAll() async {
    if (!file.existsSync()) {
      return const <Map<String, Object?>>[];
    }
    final List<String> lines = await file.readAsLines();
    return <Map<String, Object?>>[
      for (final String line in lines)
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map<Object?, Object?>).cast<String, Object?>(),
    ];
  }

  /// Deletes the record with [sessionId].
  Future<void> deleteOne(String sessionId) async {
    final List<Map<String, Object?>> kept = (await readAll())
        .where((Map<String, Object?> r) => r['session_id'] != sessionId)
        .toList();
    await file.writeAsString(
      kept.map((Map<String, Object?> r) => '${jsonEncode(r)}\n').join(),
    );
  }

  /// Deletes every record.
  Future<void> deleteAll() async {
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
