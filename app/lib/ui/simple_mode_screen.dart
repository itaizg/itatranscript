import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/caption_segment.dart';
import '../models/session_snapshot.dart';
import 'caption_screen.dart';
import 'status_banner.dart';

/// Post-v1 "simple mode": one start/stop button and extra-large text (FR-012). Settings are
/// reachable only by a long press on the title, so there is no visible way to get lost.
class SimpleModeScreen extends StatelessWidget {
  /// Creates the screen.
  const SimpleModeScreen({
    required this.snapshot,
    required this.onToggleSession,
    required this.onOpenSettings,
    super.key,
  });

  /// Live session state.
  final ValueListenable<SessionSnapshot> snapshot;

  /// Start or stop.
  final VoidCallback onToggleSession;

  /// Opened by a long press on the title.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<SessionSnapshot>(
            valueListenable: snapshot,
            builder: (BuildContext context, SessionSnapshot s, Widget? _) {
              final bool running =
                  s.state != SessionState.idle && s.state != SessionState.ended;
              final List<CaptionSegment> latest = s.segments.reversed
                  .take(3)
                  .toList()
                  .reversed
                  .toList();
              return Column(
                children: <Widget>[
                  StatusBanner(spec: bannerFor(s)),
                  GestureDetector(
                    onLongPress: onOpenSettings,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Captions', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        for (int i = 0; i < latest.length; i++)
                          CaptionLine(
                            segment: latest[latest.length - 1 - i],
                            ageIndex: i,
                            textScale: 2.6,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: onToggleSession,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(120),
                        backgroundColor: running
                            ? const Color(0xFF9C1C1C)
                            : const Color(0xFF1B7F3B),
                      ),
                      child: Text(
                        running ? 'STOP' : 'START',
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
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
