import '../core/clock.dart';
import '../models/audio_frame.dart';
import '../models/engine_event.dart';
import '../models/engine_profile.dart';
import '../models/session_snapshot.dart';

/// Audio in, events out (`contracts/engine-stream.md`). Adapters keep no state between sessions
/// and write nothing to disk.
abstract interface class EngineAdapter {
  /// Starts a session; [secrets] holds the app's own API keys.
  Future<void> open(
    EngineProfile profile,
    LanguageMode mode,
    Map<String, String> secrets,
  );

  /// Sends one gated 20 ms frame.
  Future<void> pushAudio(AudioFrame frame);

  /// Flushes, emits the remaining finals, then `closed`.
  Future<void> finish();

  /// Stops now and emits `closed`; nothing follows it.
  Future<void> cancel();

  /// Events until `closed`, which is always last.
  Stream<EngineEvent> get events;
}

/// Builds an adapter for a profile.
typedef AdapterFactory = EngineAdapter Function(
  EngineProfile profile,
  Clock clock,
);

/// Thrown when no adapter is registered for a profile's `adapter` key.
class UnknownAdapterException implements Exception {
  /// Creates the exception for [key].
  const UnknownAdapterException(this.key);

  /// The adapter key that has no factory.
  final String key;

  @override
  String toString() =>
      'UnknownAdapterException: no adapter registered for $key';
}

/// Maps `adapter` keys from `engines.yaml` to factories, so changing the engine is a settings
/// change and not a code change (FR-013).
class AdapterRegistry {
  /// Creates a registry from [factories].
  AdapterRegistry(Map<String, AdapterFactory> factories)
    : _factories = Map<String, AdapterFactory>.unmodifiable(factories);

  final Map<String, AdapterFactory> _factories;

  /// Creates the adapter for [profile], after the privacy gate.
  EngineAdapter create(EngineProfile profile, Clock clock) {
    profile.assertOpenable();
    final AdapterFactory? factory = _factories[profile.adapter];
    if (factory == null) {
      throw UnknownAdapterException(profile.adapter);
    }
    return factory(profile, clock);
  }
}
