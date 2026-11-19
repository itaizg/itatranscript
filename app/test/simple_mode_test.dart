import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/ui/simple_mode_screen.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget build(
    ValueNotifier<SessionSnapshot> snap, {
    VoidCallback? onSettings,
  }) => MaterialApp(
    home: SimpleModeScreen(
      snapshot: snap,
      onToggleSession: () {},
      onOpenSettings: onSettings ?? () {},
    ),
  );

  final ValueNotifier<SessionSnapshot> idle = ValueNotifier<SessionSnapshot>(
    SessionSnapshot.idle(LanguageMode.auto),
  );

  testWidgets('exactly one button and no visible settings entry (FR-012)', (
    t,
  ) async {
    await t.pumpWidget(build(idle));
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
    expect(find.text('START'), findsOneWidget);
  });

  testWidgets('a long press on the title opens settings', (t) async {
    bool opened = false;
    await t.pumpWidget(build(idle, onSettings: () => opened = true));
    await t.longPress(find.text('Captions'));
    expect(opened, isTrue);
  });

  testWidgets('captions are shown in extra-large text', (t) async {
    final ValueNotifier<SessionSnapshot> snap = ValueNotifier<SessionSnapshot>(
      SessionSnapshot(
        state: SessionState.live,
        languageMode: LanguageMode.auto,
        segments: const <CaptionSegment>[
          CaptionSegment(
            id: 'a',
            status: SegmentStatus.finalized,
            text: 'hello',
            lang: 'en',
            startMs: 0,
            endMs: 1,
          ),
        ],
      ),
    );
    await t.pumpWidget(build(snap));
    expect(
      t.widget<Text>(find.byKey(const Key('line_a'))).style!.fontSize!,
      greaterThan(40),
    );
    expect(find.text('STOP'), findsOneWidget);
  });
}
