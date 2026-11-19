import 'dart:async';
import 'dart:convert';

import '../core/clock.dart';
import '../models/audio_frame.dart';
import '../models/engine_event.dart';
import '../models/engine_profile.dart';
import '../models/session_snapshot.dart';
import 'engine_adapter.dart';

/// Parses an `.events.jsonl` fixture into events.
List<EngineEvent> parseEventLog(String jsonl) => List<EngineEvent>.unmodifiable(
  const LineSplitter()
      .convert(jsonl)
      .where((String l) => l.trim().isNotEmpty)
      .map((String l) => EngineEvent.fromJson(jsonDecode(l))),
);

/// Replays a recorded event log on an injected [Clock].
class FakeEngine implements EngineAdapter {
  /// Creates an engine that will replay [log] after `open`.
  FakeEngine(this._log, this._clock);

  final List<EngineEvent> _log;
  final Clock _clock;
  final StreamController<EngineEvent> _out = StreamController<EngineEvent>();
  bool _cancelled = false;
  bool _closed = false;

  /// How many audio frames the engine has been given.
  int framesReceived = 0;

  @override
  Stream<EngineEvent> get events => _out.stream;

  @override
  Future<void> open(
    EngineProfile profile,
    LanguageMode mode,
    Map<String, String> secrets,
  ) async {
    final int openedAt = _clock.nowMs();
    unawaited(_replay(openedAt));
  }

  Future<void> _replay(int openedAt) async {
    for (final EngineEvent event in _log) {
      await _clock.sleepUntil(openedAt + event.tMs);
      if (_cancelled || _closed) {
        return;
      }
      _out.add(event);
      if (event is ClosedEvent) {
        _closed = true;
        await _out.close();
        return;
      }
    }
    await _emitClosed(openedAt);
  }

  Future<void> _emitClosed(int openedAt) async {
    if (_closed) {
      return;
    }
    _closed = true;
    _out.add(ClosedEvent(tMs: _clock.nowMs() - openedAt));
    await _out.close();
  }

  @override
  Future<void> pushAudio(AudioFrame frame) async {
    framesReceived++;
  }

  @override
  Future<void> finish() async {}

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (!_closed) {
      _closed = true;
      _out.add(ClosedEvent(tMs: _clock.nowMs()));
      await _out.close();
    }
  }
}
