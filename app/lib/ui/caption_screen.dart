import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/caption_segment.dart';
import '../models/session_snapshot.dart';
import 'caption_style.dart';
import 'caption_view_controller.dart';
import 'status_banner.dart';

/// The caption screen (`contracts/caption-screen.md`). It only renders snapshots; the actions
/// are callbacks supplied by the app wiring (VI).
class CaptionScreen extends StatelessWidget {
  /// Creates the screen.
  const CaptionScreen({
    required this.snapshot,
    required this.view,
    required this.textScale,
    required this.onToggleSession,
    required this.onCycleLanguage,
    required this.onOpenSettings,
    required this.onOpenStats,
    required this.onExport,
    this.stoppedNotice,
    super.key,
  });

  /// Live session state.
  final ValueListenable<SessionSnapshot> snapshot;

  /// Freeze and scroll state.
  final CaptionViewController view;

  /// Caption text scale from settings.
  final double textScale;

  /// Start or stop.
  final VoidCallback onToggleSession;

  /// `auto → he → en`.
  final VoidCallback onCycleLanguage;

  /// Opens settings.
  final VoidCallback onOpenSettings;

  /// Opens the stats screen.
  final VoidCallback onOpenStats;

  /// Exports the transcript.
  final VoidCallback onExport;

  /// "HH:MM" of an OS kill, shown as a banner on return.
  final String? stoppedNotice;

  /// Short label of a language mode, shown on the language button.
  static String languageLabel(LanguageMode m) => switch (m) {
    LanguageMode.auto => 'Auto',
    LanguageMode.he => 'עברית',
    LanguageMode.en => 'English',
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[snapshot, view]),
            builder: (BuildContext context, Widget? _) {
              final SessionSnapshot s = snapshot.value;
              final List<CaptionSegment> shown = view.visible(s.segments);
              final bool running =
                  s.state != SessionState.idle && s.state != SessionState.ended;
              return Column(
                children: <Widget>[
                  StatusBanner(
                    spec: bannerFor(s, stoppedNotice: stoppedNotice),
                  ),
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        _CaptionList(
                          segments: shown,
                          textScale: textScale,
                          onScrollState: (bool away) =>
                              away ? view.scrolledUp() : view.reachedBottom(),
                        ),
                        if (view.showJumpToLive)
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: ActionChip(
                              key: const Key('jump_to_live'),
                              label: const Text('jump to live'),
                              onPressed: view.resume,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Controls(
                    running: running,
                    frozen: view.mode == ViewMode.frozen,
                    language: languageLabel(s.languageMode),
                    onToggleSession: onToggleSession,
                    onFreeze: () => view.mode == ViewMode.frozen
                        ? view.resume()
                        : view.freeze(s.segments),
                    onCycleLanguage: onCycleLanguage,
                    onOpenSettings: onOpenSettings,
                    onOpenStats: onOpenStats,
                    onExport: onExport,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CaptionList extends StatelessWidget {
  const _CaptionList({
    required this.segments,
    required this.textScale,
    required this.onScrollState,
  });

  final List<CaptionSegment> segments;
  final double textScale;
  final void Function(bool awayFromNewest) onScrollState;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        onScrollState(n.metrics.pixels > 48);
        return false;
      },
      child: ListView.builder(
        key: const Key('caption_list'),
        reverse: true,
        padding: const EdgeInsets.all(16),
        itemCount: segments.length,
        itemBuilder: (BuildContext context, int i) {
          final CaptionSegment s = segments[segments.length - 1 - i];
          return CaptionLine(segment: s, ageIndex: i, textScale: textScale);
        },
      ),
    );
  }
}

/// One caption line: per-segment direction, newest largest, provisional grey italic.
class CaptionLine extends StatelessWidget {
  /// Creates a line; [ageIndex] 0 is the newest.
  const CaptionLine({
    required this.segment,
    required this.ageIndex,
    required this.textScale,
    super.key,
  });

  /// The segment to show.
  final CaptionSegment segment;

  /// 0 for the newest line, then 1, 2, ...
  final int ageIndex;

  /// Text scale from settings.
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final TextDirection dir = directionFor(segment);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (segment.speakerChangeBefore) const _SpeakerDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            displayText(segment),
            key: Key('line_${segment.id}'),
            textDirection: dir,
            textAlign: dir == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
            style: styleFor(segment, ageIndex: ageIndex, scale: textScale),
          ),
        ),
      ],
    );
  }
}

class _SpeakerDivider extends StatelessWidget {
  const _SpeakerDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('speaker_divider'),
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: 10, color: Color(0xFF4FC3F7)),
          SizedBox(width: 8),
          Expanded(
            child: Divider(height: 1, thickness: 1, color: Color(0xFF4FC3F7)),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.running,
    required this.frozen,
    required this.language,
    required this.onToggleSession,
    required this.onFreeze,
    required this.onCycleLanguage,
    required this.onOpenSettings,
    required this.onOpenStats,
    required this.onExport,
  });

  final bool running;
  final bool frozen;
  final String language;
  final VoidCallback onToggleSession;
  final VoidCallback onFreeze;
  final VoidCallback onCycleLanguage;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenStats;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: FilledButton(
              key: const Key('toggle_session'),
              onPressed: onToggleSession,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                backgroundColor: running
                    ? const Color(0xFF9C1C1C)
                    : const Color(0xFF1B7F3B),
              ),
              child: Text(
                running ? 'Stop' : 'Start',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton(
              key: const Key('freeze'),
              onPressed: onFreeze,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              child: Text(
                frozen ? 'Resume' : 'Freeze',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton(
              key: const Key('language'),
              onPressed: onCycleLanguage,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              child: Text(language, style: const TextStyle(fontSize: 18)),
            ),
          ),
          PopupMenuButton<VoidCallback>(
            key: const Key('overflow'),
            icon: const Icon(Icons.more_vert),
            onSelected: (VoidCallback action) => action(),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<VoidCallback>>[
                  PopupMenuItem<VoidCallback>(
                    value: onOpenSettings,
                    child: const Text('Settings'),
                  ),
                  PopupMenuItem<VoidCallback>(
                    value: onExport,
                    child: const Text('Export transcript'),
                  ),
                  PopupMenuItem<VoidCallback>(
                    value: onOpenStats,
                    child: const Text('Session stats'),
                  ),
                ],
          ),
        ],
      ),
    );
  }
}
