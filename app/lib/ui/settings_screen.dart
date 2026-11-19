import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/engine_profile.dart';
import '../models/session_snapshot.dart';
import '../models/settings.dart';
import '../session/settings_store.dart';

/// Engines the user may pick on this device: iPhone-capable ones, and the fake one only in debug.
List<EngineProfile> selectableEngines(Map<String, EngineProfile> all) => all
    .values
    .where(
      (EngineProfile p) =>
          p.platforms.contains('ios') && (p.adapter != 'fake' || kDebugMode),
    )
    .toList();

/// "$1.20 / hour", or "free (on-device)".
String priceLabel(EngineProfile p) => p.costUsdPerHour == 0
    ? 'free (on-device)'
    : '\$${p.costUsdPerHour.toStringAsFixed(2)} / hour';

/// Settings: engine picker (FR-013), language mode, the app's own API key, price (FR-014),
/// monthly cap, and test mode (FR-025).
class SettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const SettingsScreen({
    required this.store,
    required this.profiles,
    this.onSaved,
    super.key,
  });

  /// Where settings and keys are stored.
  final SettingsStore store;

  /// All known engines.
  final Map<String, EngineProfile> profiles;

  /// Called after each change is saved.
  final ValueChanged<Settings>? onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings? _settings;
  final TextEditingController _key = TextEditingController();
  final TextEditingController _cap = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.store.load().then((Settings s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _cap.text = s.monthlyCapUsd?.toString() ?? '';
        });
      }
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _save(Settings next) async {
    setState(() => _settings = next);
    await widget.store.save(next);
    widget.onSaved?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final Settings? s = _settings;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final List<EngineProfile> engines = selectableEngines(widget.profiles);
    final EngineProfile? active = widget.profiles[s.activeEngineId];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Speech engine'),
          DropdownButton<String>(
            key: const Key('engine_picker'),
            isExpanded: true,
            value: engines.any((EngineProfile e) => e.id == s.activeEngineId)
                ? s.activeEngineId
                : null,
            items: <DropdownMenuItem<String>>[
              for (final EngineProfile e in engines)
                DropdownMenuItem<String>(
                  value: e.id,
                  child: Text('${e.displayName} – ${priceLabel(e)}'),
                ),
            ],
            onChanged: (String? id) {
              if (id != null) {
                _save(s.copyWith(activeEngineId: id));
              }
            },
          ),
          if (active != null)
            Text('Cost: ${priceLabel(active)}', key: const Key('price')),
          const SizedBox(height: 16),
          const Text('Language'),
          SegmentedButton<LanguageMode>(
            key: const Key('language_mode'),
            segments: const <ButtonSegment<LanguageMode>>[
              ButtonSegment<LanguageMode>(
                value: LanguageMode.auto,
                label: Text('Auto'),
              ),
              ButtonSegment<LanguageMode>(
                value: LanguageMode.he,
                label: Text('עברית'),
              ),
              ButtonSegment<LanguageMode>(
                value: LanguageMode.en,
                label: Text('English'),
              ),
            ],
            selected: <LanguageMode>{s.languageMode},
            onSelectionChanged: (Set<LanguageMode> m) =>
                _save(s.copyWith(languageMode: m.first)),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('api_key'),
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key for this engine (stored in the Keychain)',
            ),
            onSubmitted: (String v) async {
              await widget.store.setApiKey(s.activeEngineId, v.trim());
              _key.clear();
            },
          ),
          TextField(
            key: const Key('monthly_cap'),
            controller: _cap,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Monthly cap in USD (empty = no cap)',
            ),
            onSubmitted: (String v) {
              final double? cap = double.tryParse(v);
              _save(
                cap == null
                    ? s.copyWith(clearCap: true)
                    : s.copyWith(monthlyCapUsd: cap),
              );
            },
          ),
          SwitchListTile(
            key: const Key('test_mode'),
            title: const Text('Test mode'),
            subtitle: const Text('Add session stats to exports'),
            value: s.testMode,
            onChanged: (bool v) => _save(s.copyWith(testMode: v)),
          ),
        ],
      ),
    );
  }
}
