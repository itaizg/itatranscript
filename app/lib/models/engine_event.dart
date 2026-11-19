import 'json_reader.dart';

const Set<String> _langs = <String>{'he', 'en', 'mixed'};

/// One event from an engine (`shared/engine-events.schema.json`).
sealed class EngineEvent with JsonValue {
  /// Creates an event stamped with [tMs], the time the adapter emitted it.
  const EngineEvent(this.tMs);

  /// Validates and parses one event; throws [FormatException] on anything unexpected.
  factory EngineEvent.fromJson(Object? json) {
    final JsonReader r = JsonReader(json, 'event');
    final String type = r.string('type');
    final int t = r.integer('t_ms', min: 0);
    final EngineEvent event = switch (type) {
      'partial' => PartialEvent(
        tMs: t,
        segmentId: r.string('segment_id'),
        text: r.string('text'),
        lang: r.has('lang') ? r.oneOf('lang', _langs) : null,
        startMs: r.integer('start_ms', min: 0),
        endMs: r.optInteger('end_ms', min: 0),
      ),
      'final' => FinalEvent(
        tMs: t,
        segmentId: r.string('segment_id'),
        text: r.string('text'),
        lang: r.oneOf('lang', _langs),
        startMs: r.integer('start_ms', min: 0),
        endMs: r.integer('end_ms', min: 0),
        words: r.has('words')
            ? List<WordTiming>.unmodifiable(
                r.list('words').map((Object? w) => WordTiming._fromJson(w)),
              )
            : null,
      ),
      'speaker_change' => SpeakerChangeEvent(
        tMs: t,
        atMs: r.integer('at_ms', min: 0),
        speakerHint: r.optString('speaker_hint'),
      ),
      'health' => HealthEvent(
        tMs: t,
        state: r.oneOf('state', <String>{'ok', 'degraded', 'lost'}),
        reason: r.string('reason'),
      ),
      'usage' => UsageEvent(
        tMs: t,
        audioSecondsBilled: r.number('audio_seconds_billed', min: 0),
      ),
      'error' => ErrorEvent(
        tMs: t,
        code: r.oneOf('code', <String>{
          'auth',
          'quota',
          'network',
          'unsupported_language',
          'invalid_message',
          'internal',
        }),
        message: r.string('message'),
        retryable: r.boolean('retryable'),
      ),
      'closed' => ClosedEvent(tMs: t),
      _ => throw FormatException('event.type: unknown type $type'),
    };
    r.done();
    return event;
  }

  /// Time the adapter emitted the event (ms).
  final int tMs;

  /// The `type` discriminator.
  String get type;
}

/// Provisional text that replaces the earlier partial with the same id.
final class PartialEvent extends EngineEvent {
  /// Creates a partial.
  const PartialEvent({
    required int tMs,
    required this.segmentId,
    required this.text,
    required this.startMs,
    this.lang,
    this.endMs,
  }) : super(tMs);

  /// Segment this text belongs to.
  final String segmentId;

  /// The provisional text.
  final String text;

  /// `he`, `en`, `mixed`, or null when the engine does not say.
  final String? lang;

  /// Start of the segment (ms).
  final int startMs;

  /// End of the segment so far (ms).
  final int? endMs;

  @override
  String get type => 'partial';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'segment_id': segmentId,
    'text': text,
    'lang': ?lang,
    'start_ms': startMs,
    'end_ms': ?endMs,
  };
}

/// A word with its own timing, inside a [FinalEvent].
final class WordTiming with JsonValue {
  /// Creates a timed word.
  const WordTiming({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.lang,
  });

  factory WordTiming._fromJson(Object? json) {
    final JsonReader r = JsonReader(json, 'word');
    final WordTiming w = WordTiming(
      text: r.string('text'),
      startMs: r.integer('start_ms', min: 0),
      endMs: r.integer('end_ms', min: 0),
      lang: r.has('lang') ? r.oneOf('lang', _langs) : null,
    );
    r.done();
    return w;
  }

  /// The word.
  final String text;

  /// Start (ms).
  final int startMs;

  /// End (ms).
  final int endMs;

  /// Language of the word, if known.
  final String? lang;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'start_ms': startMs,
    'end_ms': endMs,
    'lang': ?lang,
  };
}

/// Final text for a segment. Exactly one per segment id; nothing follows it.
final class FinalEvent extends EngineEvent {
  /// Creates a final.
  const FinalEvent({
    required int tMs,
    required this.segmentId,
    required this.text,
    required this.lang,
    required this.startMs,
    required this.endMs,
    this.words,
  }) : super(tMs);

  /// Segment id.
  final String segmentId;

  /// The final text.
  final String text;

  /// `he`, `en` or `mixed`.
  final String lang;

  /// Start (ms).
  final int startMs;

  /// End (ms).
  final int endMs;

  /// Optional word timings.
  final List<WordTiming>? words;

  @override
  String get type => 'final';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'segment_id': segmentId,
    'text': text,
    'lang': lang,
    'start_ms': startMs,
    'end_ms': endMs,
    if (words != null)
      'words': words!.map((WordTiming w) => w.toJson()).toList(),
  };
}

/// A new speaker starts at [atMs]; comes before the first event of that speaker's segment.
final class SpeakerChangeEvent extends EngineEvent {
  /// Creates a speaker change.
  const SpeakerChangeEvent({
    required int tMs,
    required this.atMs,
    this.speakerHint,
  }) : super(tMs);

  /// When the new speaker starts (ms).
  final int atMs;

  /// Optional engine label for the speaker.
  final String? speakerHint;

  @override
  String get type => 'speaker_change';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'at_ms': atMs,
    'speaker_hint': ?speakerHint,
  };
}

/// Connection health; `lost` triggers the on-device fallback.
final class HealthEvent extends EngineEvent {
  /// Creates a health event.
  const HealthEvent({
    required int tMs,
    required this.state,
    required this.reason,
  }) : super(tMs);

  /// `ok`, `degraded` or `lost`.
  final String state;

  /// Short human-readable reason.
  final String reason;

  @override
  String get type => 'health';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'state': state,
    'reason': reason,
  };
}

/// Billed audio, used for cost.
final class UsageEvent extends EngineEvent {
  /// Creates a usage event.
  const UsageEvent({required int tMs, required this.audioSecondsBilled})
    : super(tMs);

  /// Seconds of audio billed so far.
  final double audioSecondsBilled;

  @override
  String get type => 'usage';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'audio_seconds_billed': audioSecondsBilled,
  };
}

/// An engine or vendor error.
final class ErrorEvent extends EngineEvent {
  /// Creates an error event.
  const ErrorEvent({
    required int tMs,
    required this.code,
    required this.message,
    required this.retryable,
  }) : super(tMs);

  /// One of auth, quota, network, unsupported_language, invalid_message, internal.
  final String code;

  /// Human-readable detail (never caption text).
  final String message;

  /// Whether retrying may help.
  final bool retryable;

  @override
  String get type => 'error';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    't_ms': tMs,
    'code': code,
    'message': message,
    'retryable': retryable,
  };
}

/// Always the last event of a stream.
final class ClosedEvent extends EngineEvent {
  /// Creates a closed event.
  const ClosedEvent({required int tMs}) : super(tMs);

  @override
  String get type => 'closed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': type, 't_ms': tMs};
}
