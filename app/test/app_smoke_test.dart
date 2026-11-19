import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/app.dart';
import 'package:itatranscript/export/transcript_export.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/models/session_snapshot.dart';
import 'package:itatranscript/session/launch_action.dart';
import 'package:itatranscript/session/session_stats.dart';
import 'package:material_ui/material_ui.dart';

import 'rig.dart';

class _NoShare implements Sharer {
  @override
  Future<void> share(String path) async {}
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('app_smoke'));
  tearDown(() => dir.deleteSync(recursive: true));

  AppDependencies deps(Rig r, {LaunchAction launch = const NoAction()}) =>
      AppDependencies(
        controller: r.controller,
        settings: r.store,
        profiles: r.profiles,
        stats: StatsStore(File('${dir.path}/stats.jsonl')),
        exporter: TranscriptExporter(
          sharer: _NoShare(),
          tempDir: () async => dir,
        ),
        launch: launch,
      );

  testWidgets('tapping Start starts the session and captions render', (
    t,
  ) async {
    final Rig r = Rig();
    await t.pumpWidget(ItaTranscriptApp(deps: deps(r)));
    await t.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    await t.tap(find.byKey(const Key('toggle_session')));
    await t.pump();
    await t.pump();
    expect(r.controller.snapshot.value.state, SessionState.starting);
    r.audio.emitFrames(30);
    await t.pump();
    await t.pump();
    r.engines.single.emit(
      const FinalEvent(
        tMs: 1,
        segmentId: 's',
        text: 'שלום',
        lang: 'he',
        startMs: 0,
        endMs: 5,
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.text('שלום'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    // Stopping runs in the real zone: StreamSubscription.cancel() futures do not resume under
    // FakeAsync. The stop path itself is covered in session_controller_test.dart.
    await t.runAsync(r.controller.stop);
    await t.pump();
    expect(r.controller.snapshot.value.state, SessionState.ended);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a start=true launch starts a session straight away (FR-011)', (
    t,
  ) async {
    final Rig r = Rig();
    await t.pumpWidget(
      ItaTranscriptApp(deps: deps(r, launch: const StartSession())),
    );
    await t.pump();
    await t.pump();
    expect(r.audio.started, isTrue);
  });

  testWidgets(
    'after an OS kill the notice "captions stopped at HH:MM" is shown',
    (t) async {
      final Rig r = Rig();
      await t.pumpWidget(
        ItaTranscriptApp(
          deps: deps(
            r,
            launch: ShowStoppedNotice(DateTime(2026, 12, 1, 14, 5)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('captions stopped at 14:05'), findsOneWidget);
    },
  );

  testWidgets('the language button cycles auto → he and saves it', (t) async {
    final Rig r = Rig();
    await t.pumpWidget(ItaTranscriptApp(deps: deps(r)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('language')));
    await t.pumpAndSettle();
    expect(find.text('עברית'), findsOneWidget);
    expect((await r.store.load()).languageMode, LanguageMode.he);
  });

  testWidgets('the overflow menu opens the settings screen', (t) async {
    final Rig r = Rig();
    await t.pumpWidget(ItaTranscriptApp(deps: deps(r)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('overflow')));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Speech engine'), findsOneWidget);
  });
}
