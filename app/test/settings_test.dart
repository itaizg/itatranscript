import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/models/settings.dart';
import 'package:itatranscript/session/settings_store.dart';

import 'fakes.dart';

void main() {
  const Settings defaults = Settings.defaults(activeEngineId: 'apple-ondevice');

  SettingsStore store(MemoryKeyValueStore prefs, MemorySecretStore secrets) =>
      SettingsStore(preferences: prefs, secrets: secrets, defaults: defaults);

  test('first run returns the defaults from data-model.md', () async {
    final Settings s = await store(
      MemoryKeyValueStore(),
      MemorySecretStore(),
    ).load();
    expect(s.languageMode, LanguageMode.auto);
    expect(s.testMode, isFalse);
    expect(s.monthlyCapUsd, isNull);
    expect(s.textScale, greaterThan(1));
  });

  test('settings round-trip through storage', () async {
    final MemoryKeyValueStore prefs = MemoryKeyValueStore();
    final SettingsStore a = store(prefs, MemorySecretStore());
    await a.save(
      defaults.copyWith(
        activeEngineId: 'x',
        monthlyCapUsd: 5,
        languageMode: LanguageMode.he,
      ),
    );
    final Settings back = await store(prefs, MemorySecretStore()).load();
    expect(back.activeEngineId, 'x');
    expect(back.monthlyCapUsd, 5);
    expect(back.languageMode, LanguageMode.he);
  });

  test('unreadable stored settings fall back to defaults', () async {
    final MemoryKeyValueStore prefs = MemoryKeyValueStore()
      ..data['settings.v1'] = '{"nope":1}';
    expect(await store(prefs, MemorySecretStore()).load(), defaults);
  });

  test(
    'API keys live only in the secret store, never in preferences',
    () async {
      final MemoryKeyValueStore prefs = MemoryKeyValueStore();
      final MemorySecretStore secrets = MemorySecretStore();
      final SettingsStore s = store(prefs, secrets);
      await s.setApiKey('google-stt-he', 'SECRET-KEY-123');
      await s.save(defaults);
      expect(await s.apiKey('google-stt-he'), 'SECRET-KEY-123');
      expect(prefs.data.values.join(), isNot(contains('SECRET-KEY-123')));
      await s.setApiKey('google-stt-he', '');
      expect(await s.apiKey('google-stt-he'), isNull);
    },
  );

  test('copyWith can clear the cap and the fallback', () {
    final Settings s = defaults.copyWith(
      monthlyCapUsd: 3,
      fallbackEngineId: 'f',
    );
    expect(
      s.copyWith(clearCap: true, clearFallback: true).monthlyCapUsd,
      isNull,
    );
    expect(s.copyWith(clearFallback: true).fallbackEngineId, isNull);
  });
}
