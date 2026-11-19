import 'json_reader.dart';
import 'session_snapshot.dart';

/// The one immutable settings model; it holds the only defaults (VI, IX).
final class Settings with JsonValue {
  /// Creates settings. Defaults come from the profile files via [Settings.defaults].
  const Settings({
    required this.activeEngineId,
    required this.fallbackEngineId,
    required this.languageMode,
    required this.testMode,
    required this.monthlyCapUsd,
    required this.textScale,
  });

  /// The defaults of data-model.md, with engines taken from the caller (decision.md).
  const Settings.defaults({required this.activeEngineId, this.fallbackEngineId})
    : languageMode = LanguageMode.auto,
      testMode = false,
      monthlyCapUsd = null,
      textScale = 1.6;

  /// Parses stored settings.
  factory Settings.fromJson(Object? json) {
    final JsonReader r = JsonReader(json, 'settings');
    final Settings s = Settings(
      activeEngineId: r.string('active_engine_id'),
      fallbackEngineId: r.optString('fallback_engine_id'),
      languageMode: LanguageMode.values.byName(
        r.oneOf(
          'language_mode',
          LanguageMode.values.map((LanguageMode m) => m.name).toSet(),
        ),
      ),
      testMode: r.boolean('test_mode'),
      monthlyCapUsd: r.has('monthly_cap_usd')
          ? r.number('monthly_cap_usd', min: 0)
          : null,
      textScale: r.number('text_scale', min: 0.5),
    );
    r.done();
    return s;
  }

  /// Engine used for captions.
  final String activeEngineId;

  /// On-device engine used when the active one is lost; null for none.
  final String? fallbackEngineId;

  /// Hebrew, English or automatic.
  final LanguageMode languageMode;

  /// Adds session stats to exports (FR-025).
  final bool testMode;

  /// Monthly spending cap in USD; null means no cap.
  final double? monthlyCapUsd;

  /// Caption text scale (SC-006: large by default).
  final double textScale;

  /// Copy with some fields replaced; the nullable ones use the `clear` flags to reset.
  Settings copyWith({
    String? activeEngineId,
    String? fallbackEngineId,
    bool clearFallback = false,
    LanguageMode? languageMode,
    bool? testMode,
    double? monthlyCapUsd,
    bool clearCap = false,
    double? textScale,
  }) => Settings(
    activeEngineId: activeEngineId ?? this.activeEngineId,
    fallbackEngineId: clearFallback
        ? null
        : (fallbackEngineId ?? this.fallbackEngineId),
    languageMode: languageMode ?? this.languageMode,
    testMode: testMode ?? this.testMode,
    monthlyCapUsd: clearCap ? null : (monthlyCapUsd ?? this.monthlyCapUsd),
    textScale: textScale ?? this.textScale,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'active_engine_id': activeEngineId,
    'fallback_engine_id': ?fallbackEngineId,
    'language_mode': languageMode.name,
    'test_mode': testMode,
    'monthly_cap_usd': ?monthlyCapUsd,
    'text_scale': textScale,
  };
}
