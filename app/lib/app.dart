import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'export/transcript_export.dart';
import 'models/engine_profile.dart';
import 'models/session_snapshot.dart';
import 'models/settings.dart';
import 'session/launch_action.dart';
import 'session/launch_channel.dart';
import 'session/session_controller.dart';
import 'session/session_stats.dart';
import 'session/settings_store.dart';
import 'ui/caption_screen.dart';
import 'ui/caption_view_controller.dart';
import 'ui/settings_screen.dart';
import 'ui/stats_screen.dart';

/// Everything the app needs, built once at startup and passed in (VI).
class AppDependencies {
  /// Creates the dependency bundle.
  const AppDependencies({
    required this.controller,
    required this.settings,
    required this.profiles,
    required this.stats,
    required this.exporter,
    required this.launch,
    this.batteryPoll = const Duration(minutes: 1),
  });

  /// The session.
  final SessionController controller;

  /// Settings and keys.
  final SettingsStore settings;

  /// Known engines.
  final Map<String, EngineProfile> profiles;

  /// Session stats file.
  final StatsStore stats;

  /// Transcript export.
  final TranscriptExporter exporter;

  /// What to do right after launch.
  final LaunchAction launch;

  /// How often to sample the battery and refresh the liveness marker.
  final Duration batteryPoll;
}

/// The app: the caption screen plus routes to settings and stats.
class ItaTranscriptApp extends StatefulWidget {
  /// Creates the app.
  const ItaTranscriptApp({required this.deps, super.key});

  /// Injected collaborators.
  final AppDependencies deps;

  @override
  State<ItaTranscriptApp> createState() => _ItaTranscriptAppState();
}

class _ItaTranscriptAppState extends State<ItaTranscriptApp> {
  final CaptionViewController _view = CaptionViewController();
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();
  Timer? _poll;
  double _scale = 1.6;
  DateTime? _startedAt;
  String? _stoppedNotice;

  SessionController get _controller => widget.deps.controller;

  @override
  void initState() {
    super.initState();
    _controller.snapshot.addListener(_onSnapshot);
    widget.deps.settings.load().then((Settings s) {
      if (mounted) {
        setState(() => _scale = s.textScale);
      }
    });
    LaunchChannel().listenForStart(() {
      final SessionState state = _controller.snapshot.value.state;
      if (state == SessionState.idle || state == SessionState.ended) {
        unawaited(_start());
      }
    });
    final LaunchAction launch = widget.deps.launch;
    if (launch is StartSession) {
      unawaited(_start());
    } else if (launch is ShowStoppedNotice) {
      _stoppedNotice = launch.label;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.snapshot.removeListener(_onSnapshot);
    _view.dispose();
    super.dispose();
  }

  void _onSnapshot() {
    final SessionState state = _controller.snapshot.value.state;
    if (state == SessionState.starting && _poll == null) {
      _poll = Timer.periodic(
        widget.deps.batteryPoll,
        (Timer _) => unawaited(_controller.checkBattery()),
      );
    }
    if (state == SessionState.ended) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _start() async {
    _startedAt = DateTime.now();
    setState(() => _stoppedNotice = null);
    await _controller.start();
  }

  Future<void> _toggle() async {
    final SessionState state = _controller.snapshot.value.state;
    if (state == SessionState.idle || state == SessionState.ended) {
      await _start();
    } else {
      await _controller.stop();
    }
  }

  Future<void> _cycleLanguage() async {
    final Settings s = await widget.deps.settings.load();
    final LanguageMode current = _controller.snapshot.value.languageMode;
    final LanguageMode next =
        LanguageMode.values[(current.index + 1) % LanguageMode.values.length];
    _controller.setLanguageMode(next);
    await widget.deps.settings.save(s.copyWith(languageMode: next));
  }

  Future<void> _export() async {
    final Settings s = await widget.deps.settings.load();
    final DateTime started = _startedAt ?? DateTime.now();
    Map<String, Object?>? stats;
    if (s.testMode) {
      final List<Map<String, Object?>> all = await widget.deps.stats.readAll();
      stats = all.isEmpty ? null : all.last;
    }
    try {
      await widget.deps.exporter.export(
        fileName: exportFileName(started),
        body: buildTranscript(
          segments: _controller.segments,
          startedAt: started,
          duration: DateTime.now().difference(started),
          engineId: s.activeEngineId,
          mode: _controller.snapshot.value.languageMode.name,
          statsWhenTestMode: stats,
        ),
      );
    } on ExportFailure catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    final BuildContext? context = _nav.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _push(Widget page) => unawaited(
    _nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page)),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: CaptionScreen(
        snapshot: _controller.snapshot,
        view: _view,
        textScale: _scale,
        stoppedNotice: _stoppedNotice,
        onToggleSession: () => unawaited(_toggle()),
        onCycleLanguage: () => unawaited(_cycleLanguage()),
        onOpenSettings: () => _push(
          SettingsScreen(
            store: widget.deps.settings,
            profiles: widget.deps.profiles,
            onSaved: (Settings s) => setState(() => _scale = s.textScale),
          ),
        ),
        onOpenStats: () => _push(StatsScreen(store: widget.deps.stats)),
        onExport: () => unawaited(_export()),
      ),
    );
  }
}
