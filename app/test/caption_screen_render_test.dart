import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/ui/caption_screen.dart';
import 'package:itatranscript/ui/caption_view_controller.dart';
import 'package:material_ui/material_ui.dart';

CaptionSegment _seg(
  String id,
  String text, {
  String lang = 'en',
  SegmentStatus status = SegmentStatus.finalized,
  bool change = false,
}) => CaptionSegment(
  id: id,
  status: status,
  text: text,
  lang: lang,
  startMs: 0,
  endMs: 1,
  speakerChangeBefore: change,
);

Widget _screen(
  ValueNotifier<SessionSnapshot> snap,
  CaptionViewController view, {
  VoidCallback? onToggle,
}) => MaterialApp(
  home: CaptionScreen(
    snapshot: snap,
    view: view,
    textScale: 1.6,
    onToggleSession: onToggle ?? () {},
    onCycleLanguage: () {},
    onOpenSettings: () {},
    onOpenStats: () {},
    onExport: () {},
  ),
);

ValueNotifier<SessionSnapshot> _snap(
  List<CaptionSegment> segments, {
  SessionState state = SessionState.live,
}) => ValueNotifier<SessionSnapshot>(
  SessionSnapshot(
    state: state,
    languageMode: LanguageMode.auto,
    segments: segments,
  ),
);

TextStyle _style(WidgetTester t, String id) =>
    t.widget<Text>(find.byKey(Key('line_$id'))).style!;

void main() {
  testWidgets(
    'provisional and final text are styled differently, and the newest is largest',
    (t) async {
      final snap = _snap(<CaptionSegment>[
        _seg('old', 'older line'),
        _seg('new', 'newest line', status: SegmentStatus.provisional),
      ]);
      await t.pumpWidget(_screen(snap, CaptionViewController()));
      final TextStyle provisional = _style(t, 'new');
      final TextStyle finalized = _style(t, 'old');
      expect(provisional.fontStyle, FontStyle.italic);
      expect(finalized.fontStyle, FontStyle.normal);
      expect(provisional.color, isNot(finalized.color));
      expect(provisional.fontSize!, greaterThan(finalized.fontSize!));
    },
  );

  testWidgets(
    'a Hebrew segment is right-to-left and right-aligned; English is left-aligned',
    (t) async {
      final snap = _snap(<CaptionSegment>[
        _seg('en', 'hello there'),
        _seg('he', 'שלום לכולם', lang: 'he'),
      ]);
      await t.pumpWidget(_screen(snap, CaptionViewController()));
      final Text he = t.widget<Text>(find.byKey(const Key('line_he')));
      final Text en = t.widget<Text>(find.byKey(const Key('line_en')));
      expect(he.textDirection, TextDirection.rtl);
      expect(he.textAlign, TextAlign.right);
      expect(en.textDirection, TextDirection.ltr);
      expect(en.textAlign, TextAlign.left);
    },
  );

  testWidgets('an unknown-language segment shows [unrecognized]', (t) async {
    final snap = _snap(<CaptionSegment>[_seg('u', '???', lang: 'unknown')]);
    await t.pumpWidget(_screen(snap, CaptionViewController()));
    expect(find.text('[unrecognized]'), findsOneWidget);
    expect(find.text('???'), findsNothing);
  });

  testWidgets(
    'a divider appears before a segment with speaker_change_before, and only there',
    (t) async {
      final snap = _snap(<CaptionSegment>[
        _seg('a', 'first'),
        _seg('b', 'second', change: true),
        _seg('c', 'third'),
      ]);
      await t.pumpWidget(_screen(snap, CaptionViewController()));
      expect(find.byKey(const Key('speaker_divider')), findsOneWidget);
    },
  );

  testWidgets(
    'freeze holds the screen, shows the jump chip, and jump to live resumes (FR-009/010)',
    (t) async {
      final snap = _snap(<CaptionSegment>[_seg('a', 'first')]);
      final view = CaptionViewController();
      await t.pumpWidget(_screen(snap, view));
      expect(find.byKey(const Key('jump_to_live')), findsNothing);
      await t.tap(find.byKey(const Key('freeze')));
      await t.pump();
      expect(view.mode, ViewMode.frozen);
      snap.value = snap.value.copyWith(
        segments: <CaptionSegment>[
          _seg('a', 'first'),
          _seg('b', 'arrived while frozen'),
        ],
      );
      await t.pump();
      expect(find.text('arrived while frozen'), findsNothing);
      expect(find.byKey(const Key('jump_to_live')), findsOneWidget);
      await t.tap(find.byKey(const Key('jump_to_live')));
      await t.pump();
      expect(view.mode, ViewMode.following);
      expect(find.text('arrived while frozen'), findsOneWidget);
    },
  );

  testWidgets('start and stop reflect the session state', (t) async {
    final snap = _snap(const <CaptionSegment>[], state: SessionState.idle);
    int toggles = 0;
    await t.pumpWidget(
      _screen(snap, CaptionViewController(), onToggle: () => toggles++),
    );
    expect(find.text('Start'), findsOneWidget);
    await t.tap(find.byKey(const Key('toggle_session')));
    expect(toggles, 1);
    snap.value = snap.value.copyWith(state: SessionState.live);
    await t.pump();
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('the language button shows the current mode', (t) async {
    final snap = _snap(const <CaptionSegment>[]);
    await t.pumpWidget(_screen(snap, CaptionViewController()));
    expect(find.text('Auto'), findsOneWidget);
    snap.value = snap.value.copyWith(languageMode: LanguageMode.he);
    await t.pump();
    expect(find.text('עברית'), findsOneWidget);
  });
}
