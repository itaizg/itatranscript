import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/models/engine_profile.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/models/settings.dart';
import 'package:itatranscript/session/settings_store.dart';
import 'package:itatranscript/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'support.dart';

void main() {
  late Map<String, EngineProfile> profiles;
  late MemoryKeyValueStore prefs;
  late MemorySecretStore secrets;
  late SettingsStore store;

  setUp(() {
    profiles = parseEngines(readShared('engines.yaml'));
    prefs = MemoryKeyValueStore();
    secrets = MemorySecretStore();
    store = SettingsStore(
      preferences: prefs,
      secrets: secrets,
      defaults: const Settings.defaults(activeEngineId: 'apple-ondevice'),
    );
  });

  testWidgets('picking an engine updates Settings.active_engine_id (FR-013)', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(store: store, profiles: profiles),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('engine_picker')));
    await t.pumpAndSettle();
    final EngineProfile other = selectableEngines(profiles)
        .firstWhere((EngineProfile e) => e.id != 'apple-ondevice');
    await t.tap(find.text('${other.displayName} – ${priceLabel(other)}').last);
    await t.pumpAndSettle();
    expect((await store.load()).activeEngineId, other.id);
  });

  testWidgets('the price of the active engine is shown (FR-014)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(store: store, profiles: profiles),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Cost: free (on-device)'), findsOneWidget);
  });

  testWidgets('test mode, language mode and the cap are saved', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(store: store, profiles: profiles),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('test_mode')));
    await t.pumpAndSettle();
    await t.tap(find.text('עברית'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('monthly_cap')), '12.5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final Settings s = await store.load();
    expect(s.testMode, isTrue);
    expect(s.languageMode, LanguageMode.he);
    expect(s.monthlyCapUsd, 12.5);
  });

  testWidgets('the API key goes to the secret store, not the preferences', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(store: store, profiles: profiles),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('api_key')), 'my-secret-key');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(await store.apiKey('apple-ondevice'), 'my-secret-key');
    expect(prefs.data.values.join(), isNot(contains('my-secret-key')));
  });
}
