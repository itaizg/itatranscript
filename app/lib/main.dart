import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'capture/audio_source.dart';
import 'core/clock.dart';
import 'engines/android_speech_adapter.dart';
import 'engines/apple_speech_adapter.dart';
import 'engines/engine_adapter.dart';
import 'engines/fake_engine.dart';
import 'engines/profiles.dart';
import 'gate/silero_onnx_model.dart';
import 'gate/speech_gate.dart';
import 'models/engine_profile.dart';
import 'models/pipeline_config.dart';
import 'models/settings.dart';
import 'session/battery_watch.dart';
import 'session/cost_meter.dart';
import 'session/launch_action.dart';
import 'session/launch_channel.dart';
import 'session/session_controller.dart';
import 'session/session_stats.dart';
import 'session/settings_store.dart';
import 'export/transcript_export.dart';

/// Engine used until `decision.md` (task T049) names one. On-device, free, and needs no key.
const String kInterimEngineId = 'apple-ondevice';

/// Entry point: loads the shared files, builds the collaborators, and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
  // Logs never contain caption text or keys; only error types and counts.
  Logger.root.onRecord.listen(
    (LogRecord r) =>
        debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );

  final String enginesYaml = await rootBundle.loadString(
    'assets/shared/engines.yaml',
  );
  final String pipelineYaml = await rootBundle.loadString(
    'assets/shared/pipeline.yaml',
  );
  final Uint8List modelBytes = (await rootBundle.load(
    'assets/shared/models/silero_vad.onnx',
  )).buffer.asUint8List();
  final Map<String, EngineProfile> profiles = parseEngines(enginesYaml);
  final PipelineConfig config = parsePipeline(pipelineYaml, modelBytes);

  final KeyValueStore prefs = PreferencesStore(SharedPreferencesAsync());
  final SettingsStore settings = SettingsStore(
    preferences: prefs,
    secrets: const KeychainStore(FlutterSecureStorage()),
    defaults: const Settings.defaults(activeEngineId: kInterimEngineId),
  );
  final Settings stored = await settings.load();
  final Directory documents = await getApplicationDocumentsDirectory();
  final StatsStore stats = StatsStore(File('${documents.path}/stats.jsonl'));
  await stats.recoverOrphan();
  final List<Map<String, Object?>> past = await stats.readAll();

  final String debugFixture = kDebugMode
      ? await rootBundle.loadString(
          'assets/shared/fixtures/partial-then-final.events.jsonl',
        )
      : '';
  final Clock clock = SystemClock();
  final SileroOnnxModel model = SileroOnnxModel(modelBytes);
  final AdapterRegistry registry = AdapterRegistry(<String, AdapterFactory>{
    'apple_speech': (EngineProfile p, Clock c) => AppleSpeechAdapter(),
    'android_speech': (EngineProfile p, Clock c) => AndroidSpeechAdapter(),
    if (kDebugMode)
      'fake': (EngineProfile p, Clock c) =>
          FakeEngine(parseEventLog(debugFixture), c),
  });

  final SessionController controller = SessionController(
    audio: PlatformAudioSource(),
    gateFactory: () => SpeechGate(model, config.vad),
    settings: settings,
    profiles: profiles,
    registry: registry,
    clock: clock,
    config: config,
    extras: SessionExtras(
      stats: stats,
      costMeter: await CostMeter.load(
        capUsd: stored.monthlyCapUsd,
        store: prefs,
      ),
      battery: PlatformBatteryReader(),
      connectivity: Connectivity().onConnectivityChanged.map(
        (List<ConnectivityResult> r) => !r.contains(ConnectivityResult.none),
      ),
      pipelineSha256: sha256.convert(pipelineYaml.codeUnits).toString(),
    ),
  );

  runApp(
    ItaTranscriptApp(
      deps: AppDependencies(
        controller: controller,
        settings: settings,
        profiles: profiles,
        stats: stats,
        exporter: const TranscriptExporter(),
        launch: decideLaunchAction(
          launchArguments: await LaunchChannel().arguments(),
          lastStats: past.isEmpty ? null : past.last,
        ),
      ),
    ),
  );
}
