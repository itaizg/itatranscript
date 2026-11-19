import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';

/// Plain key-value storage for non-secret settings.
abstract interface class KeyValueStore {
  /// Returns the stored string, or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);
}

/// Secret storage (the iOS Keychain in the app).
abstract interface class SecretStore {
  /// Returns the stored secret, or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes the secret.
  Future<void> delete(String key);
}

/// [KeyValueStore] on `shared_preferences`.
class PreferencesStore implements KeyValueStore {
  /// Creates a store over [_prefs].
  const PreferencesStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

/// [SecretStore] on the Keychain via `flutter_secure_storage`.
class KeychainStore implements SecretStore {
  /// Creates a store over [_storage].
  const KeychainStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Loads and saves [Settings]; API keys live only in the [SecretStore] and are never logged.
class SettingsStore {
  /// Creates a store; [defaults] is returned until the user changes something.
  const SettingsStore({
    required this._preferences,
    required this._secrets,
    required this.defaults,
  });

  /// The only defaults in the app.
  final Settings defaults;
  final KeyValueStore _preferences;
  final SecretStore _secrets;

  static const String _settingsKey = 'settings.v1';

  /// Reads the stored settings, falling back to [defaults] on first run or if unreadable.
  Future<Settings> load() async {
    final String? raw = await _preferences.read(_settingsKey);
    if (raw == null) {
      return defaults;
    }
    try {
      return Settings.fromJson(jsonDecode(raw));
    } on FormatException {
      return defaults;
    }
  }

  /// Persists [settings].
  Future<void> save(Settings settings) =>
      _preferences.write(_settingsKey, jsonEncode(settings.toJson()));

  /// The app's own API key for [engineId], or null.
  Future<String?> apiKey(String engineId) => _secrets.read('api_key.$engineId');

  /// Stores the app's API key for [engineId]; an empty key deletes it.
  Future<void> setApiKey(String engineId, String key) => key.isEmpty
      ? _secrets.delete('api_key.$engineId')
      : _secrets.write('api_key.$engineId', key);
}
