import 'json_reader.dart';

/// What a vendor does with audio (FR-020).
final class Privacy with JsonValue {
  /// Creates a privacy record.
  const Privacy({
    required this.retainsAudio,
    required this.trainsOnAudio,
    required this.optOutRequired,
    required this.termsSource,
    required this.termsCheckedOn,
  });

  /// Parses the `privacy` object of a profile.
  factory Privacy.fromJson(Object? json, String what) {
    final JsonReader r = JsonReader(json, what);
    final Privacy p = Privacy(
      retainsAudio: r.boolean('retains_audio'),
      trainsOnAudio: r.boolean('trains_on_audio'),
      optOutRequired: r.boolean('opt_out_required'),
      termsSource: r.string('terms_source'),
      termsCheckedOn: r.string('terms_checked_on'),
    );
    r.done();
    return p;
  }

  /// The vendor keeps audio.
  final bool retainsAudio;

  /// The vendor trains on audio.
  final bool trainsOnAudio;

  /// An opt-out exists and must be applied.
  final bool optOutRequired;

  /// Where the terms were read.
  final String termsSource;

  /// When they were read, or `unverified`.
  final String termsCheckedOn;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'retains_audio': retainsAudio,
    'trains_on_audio': trainsOnAudio,
    'opt_out_required': optOutRequired,
    'terms_source': termsSource,
    'terms_checked_on': termsCheckedOn,
  };
}

/// Thrown when an engine's terms fail the privacy gate (FR-020).
class PrivacyGateException implements Exception {
  /// Creates the exception with the reason.
  const PrivacyGateException(this.message);

  /// Why the engine was refused.
  final String message;

  @override
  String toString() => 'PrivacyGateException: $message';
}

/// One engine as listed in `shared/engines.yaml`.
final class EngineProfile with JsonValue {
  /// Creates a profile; use [EngineProfile.fromJson] for file data.
  const EngineProfile({
    required this.id,
    required this.displayName,
    required this.adapter,
    required this.runsOn,
    required this.platforms,
    required this.languages,
    required this.supportsCodeSwitching,
    required this.supportsSpeakerChanges,
    required this.canBeFallback,
    required this.costUsdPerHour,
    required this.privacy,
    this.options = const <String, Object>{},
  });

  /// Parses and validates one profile, enforcing the load-time rules.
  factory EngineProfile.fromJson(Object? json) {
    final JsonReader r = JsonReader(json, 'engine');
    final EngineProfile p = EngineProfile(
      id: r.string('id'),
      displayName: r.string('display_name'),
      adapter: r.string('adapter'),
      runsOn: r.oneOf('runs_on', <String>{'cloud', 'device', 'mac'}),
      platforms: List<String>.unmodifiable(r.list('platforms').cast<String>()),
      languages: List<String>.unmodifiable(r.list('languages').cast<String>()),
      supportsCodeSwitching: r.boolean('supports_code_switching'),
      supportsSpeakerChanges: r.boolean('supports_speaker_changes'),
      canBeFallback: r.boolean('can_be_fallback'),
      costUsdPerHour: r.number('cost_usd_per_hour', min: 0),
      privacy: Privacy.fromJson(r.object('privacy').rawMap, 'engine.privacy'),
      options: r.scalarMap('options'),
    );
    r.done();
    if (p.runsOn == 'device' && p.costUsdPerHour != 0) {
      throw FormatException('${p.id}: a device profile must cost 0');
    }
    if (p.canBeFallback && p.runsOn != 'device') {
      throw FormatException('${p.id}: only a device profile can be a fallback');
    }
    if (p.languages.isEmpty) {
      throw FormatException('${p.id}: needs at least one language');
    }
    return p;
  }

  /// Unique id, e.g. `google-stt-he`.
  final String id;

  /// Name shown in settings.
  final String displayName;

  /// Adapter key.
  final String adapter;

  /// `cloud`, `device` or `mac`.
  final String runsOn;

  /// Platforms this engine can run on.
  final List<String> platforms;

  /// Languages supported (`he`, `en`).
  final List<String> languages;

  /// Whether the engine handles mixed-language speech.
  final bool supportsCodeSwitching;

  /// Whether the engine emits speaker changes.
  final bool supportsSpeakerChanges;

  /// Whether the engine may be the on-device fallback.
  final bool canBeFallback;

  /// Price per hour of audio.
  final double costUsdPerHour;

  /// Retention and training terms.
  final Privacy privacy;

  /// Adapter-specific options.
  final Map<String, Object> options;

  /// Throws [PrivacyGateException] if the engine keeps audio, or trains on it with no opt-out.
  void assertOpenable() {
    if (privacy.retainsAudio) {
      throw PrivacyGateException('$id: vendor retains audio');
    }
    if (privacy.trainsOnAudio && !privacy.optOutRequired) {
      throw PrivacyGateException(
        '$id: vendor trains on audio and offers no opt-out',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'display_name': displayName,
    'adapter': adapter,
    'runs_on': runsOn,
    'platforms': platforms,
    'languages': languages,
    'supports_code_switching': supportsCodeSwitching,
    'supports_speaker_changes': supportsSpeakerChanges,
    'can_be_fallback': canBeFallback,
    'cost_usd_per_hour': costUsdPerHour,
    'privacy': privacy.toJson(),
    'options': options,
  };
}
