import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/ui/caption_screen.dart';
import 'package:itatranscript/ui/caption_view_controller.dart';
import 'package:itatranscript/ui/status_banner.dart';
import 'package:material_ui/material_ui.dart';

SessionSnapshot _s(
  SessionState state, {
  String? error,
  String? pause,
  bool battery = false,
  int? minutes,
  String cost = 'ok',
}) => SessionSnapshot(
  state: state,
  languageMode: LanguageMode.auto,
  segments: const <CaptionSegment>[],
  errorMessage: error,
  pauseReason: pause,
  batteryLow: battery,
  batteryMinutesLeft: minutes,
  costLevel: cost,
);

void main() {
  test('each state maps to the right banner (contracts/caption-screen.md)', () {
    expect(bannerFor(_s(SessionState.live)), isNull);
    expect(
      bannerFor(_s(SessionState.fallback))!.text,
      'offline – lower accuracy',
    );
    expect(
      bannerFor(_s(SessionState.pausedOffline))!.text,
      'captions paused – no connection',
    );
    expect(
      bannerFor(_s(SessionState.pausedMic, pause: 'phone call'))!.text,
      'paused – mic in use (phone call)',
    );
    expect(
      bannerFor(_s(SessionState.live, battery: true, minutes: 12))!.text,
      'battery low – about 12 min left',
    );
    expect(bannerFor(_s(SessionState.live, cost: 'warn90'))!.key, 'cost_warn');
    expect(
      bannerFor(_s(SessionState.idle), stoppedNotice: '14:05')!.text,
      'captions stopped at 14:05',
    );
    expect(
      bannerFor(_s(SessionState.ended, error: 'Captions stopped: StateError'))!
          .key,
      'error',
    );
  });

  test('stopped states are red and degraded states are amber', () {
    expect(
      bannerFor(_s(SessionState.pausedOffline))!.color,
      const Color(0xFF9C1C1C),
    );
    expect(
      bannerFor(_s(SessionState.fallback))!.color,
      const Color(0xFFB26A00),
    );
  });

  testWidgets(
    'the banner sits above the list and does not cover the newest line',
    (t) async {
      final snap = ValueNotifier<SessionSnapshot>(
        SessionSnapshot(
          state: SessionState.fallback,
          languageMode: LanguageMode.auto,
          segments: const <CaptionSegment>[
            CaptionSegment(
              id: 'n',
              status: SegmentStatus.finalized,
              text: 'newest',
              lang: 'en',
              startMs: 0,
              endMs: 1,
            ),
          ],
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: CaptionScreen(
            snapshot: snap,
            view: CaptionViewController(),
            textScale: 1.6,
            onToggleSession: () {},
            onCycleLanguage: () {},
            onOpenSettings: () {},
            onOpenStats: () {},
            onExport: () {},
          ),
        ),
      );
      final Rect banner = t.getRect(find.byKey(const Key('banner_fallback')));
      final Rect newest = t.getRect(find.byKey(const Key('line_n')));
      expect(find.text('offline – lower accuracy'), findsOneWidget);
      expect(banner.bottom, lessThanOrEqualTo(newest.top));
    },
  );
}
