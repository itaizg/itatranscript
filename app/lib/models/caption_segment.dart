import 'json_reader.dart';

/// Whether a segment may still change.
enum SegmentStatus {
  /// Still being refined by the engine.
  provisional,

  /// Never changes again.
  finalized,
}

/// Which engine produced a segment.
enum EngineRole {
  /// The engine the user selected.
  active,

  /// The on-device fallback engine.
  fallback,
}

/// One line of captions.
final class CaptionSegment with JsonValue {
  /// Creates a segment.
  const CaptionSegment({
    required this.id,
    required this.status,
    required this.text,
    required this.lang,
    required this.startMs,
    required this.endMs,
    this.speakerChangeBefore = false,
    this.engineRole = EngineRole.active,
  });

  /// Segment id, namespaced by adapter instance.
  final String id;

  /// Provisional or final.
  final SegmentStatus status;

  /// The text.
  final String text;

  /// `he`, `en`, `mixed` or `unknown`.
  final String lang;

  /// Start (ms since session start).
  final int startMs;

  /// End (ms since session start).
  final int endMs;

  /// A speaker change precedes this segment (FR-006).
  final bool speakerChangeBefore;

  /// Which engine produced it.
  final EngineRole engineRole;

  /// Whether the text should be shown as `[unrecognized]`.
  bool get isUnrecognized => lang == 'unknown';

  /// Copy with some fields replaced.
  CaptionSegment copyWith({
    SegmentStatus? status,
    String? text,
    String? lang,
    int? endMs,
    bool? speakerChangeBefore,
  }) => CaptionSegment(
    id: id,
    status: status ?? this.status,
    text: text ?? this.text,
    lang: lang ?? this.lang,
    startMs: startMs,
    endMs: endMs ?? this.endMs,
    speakerChangeBefore: speakerChangeBefore ?? this.speakerChangeBefore,
    engineRole: engineRole,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'text': text,
    'lang': lang,
    'start_ms': startMs,
    'end_ms': endMs,
    'speaker_change_before': speakerChangeBefore,
    'engine_role': engineRole.name,
  };
}
