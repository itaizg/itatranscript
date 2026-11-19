import 'caption_segment.dart';
import 'json_reader.dart';

/// Session lifecycle (data-model.md).
enum SessionState {
  /// Not started.
  idle,

  /// Opening the engine; no audio yet.
  starting,

  /// Captions are flowing.
  live,

  /// Running on the on-device fallback engine.
  fallback,

  /// The microphone was taken by another app or call.
  pausedMic,

  /// No connection and no fallback for this language.
  pausedOffline,

  /// Stopped.
  ended,
}

/// Language mode (FR-004).
enum LanguageMode {
  /// Detect Hebrew, English or mixed speech.
  auto,

  /// Hebrew only.
  he,

  /// English only.
  en,
}

/// An immutable view of the session, handed to the UI (VI).
final class SessionSnapshot with JsonValue {
  /// Creates a snapshot; [segments] is copied into an unmodifiable list.
  SessionSnapshot({
    required this.state,
    required this.languageMode,
    required List<CaptionSegment> segments,
    this.errorMessage,
    this.pauseReason,
    this.batteryLow = false,
    this.batteryMinutesLeft,
    this.costLevel = 'ok',
  }) : segments = List<CaptionSegment>.unmodifiable(segments);

  /// The state before anything starts.
  factory SessionSnapshot.idle(LanguageMode mode) => SessionSnapshot(
    state: SessionState.idle,
    languageMode: mode,
    segments: const <CaptionSegment>[],
  );

  /// Lifecycle state.
  final SessionState state;

  /// Current language mode.
  final LanguageMode languageMode;

  /// All segments in order.
  final List<CaptionSegment> segments;

  /// A visible error, if the session hit one (FR-021).
  final String? errorMessage;

  /// Why the session is paused, if it is.
  final String? pauseReason;

  /// The battery-low warning is showing.
  final bool batteryLow;

  /// Estimated minutes of battery left, if known.
  final int? batteryMinutesLeft;

  /// `ok`, `warn90` or `capReached` (see CostLevel).
  final String costLevel;

  /// Copy with some fields replaced.
  SessionSnapshot copyWith({
    SessionState? state,
    LanguageMode? languageMode,
    List<CaptionSegment>? segments,
    String? errorMessage,
    String? pauseReason,
    bool? batteryLow,
    int? batteryMinutesLeft,
    String? costLevel,
  }) => SessionSnapshot(
    state: state ?? this.state,
    languageMode: languageMode ?? this.languageMode,
    segments: segments ?? this.segments,
    errorMessage: errorMessage ?? this.errorMessage,
    pauseReason: pauseReason ?? this.pauseReason,
    batteryLow: batteryLow ?? this.batteryLow,
    batteryMinutesLeft: batteryMinutesLeft ?? this.batteryMinutesLeft,
    costLevel: costLevel ?? this.costLevel,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'language_mode': languageMode.name,
    'segments': segments.map((CaptionSegment s) => s.toJson()).toList(),
    'error_message': ?errorMessage,
    'pause_reason': ?pauseReason,
    'battery_low': batteryLow,
    'battery_minutes_left': ?batteryMinutesLeft,
    'cost_level': costLevel,
  };
}
