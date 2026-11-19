import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/export/transcript_export.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/session/session_controller.dart';
import 'package:itatranscript/session/session_stats.dart';
import 'package:logging/logging.dart';

import 'rig.dart';

class _OkSharer implements Sharer {
  @override
  Future<void> share(String path) async {}
}

void main() {
  const String caption = 'CONFIDENTIAL-CAPTION-TEXT';
  const String apiKey = 'sk-test-SECRET-KEY-999';

  late Directory documents;
  late Directory temp;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('docs');
    temp = Directory.systemTemp.createTempSync('tmp');
    records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    documents.deleteSync(recursive: true);
    temp.deleteSync(recursive: true);
  });

  Future<Rig> runSession({bool fail = false}) async {
    final StatsStore stats = StatsStore(File('${documents.path}/stats.jsonl'));
    final Rig r = Rig(extras: SessionExtras(stats: stats));
    await r.store.setApiKey('fake', apiKey);
    await r.controller.start();
    await r.speak();
    r.engines.single
      ..emit(
        const PartialEvent(
          tMs: 1,
          segmentId: 's',
          text: caption,
          lang: 'en',
          startMs: 0,
        ),
      )
      ..emit(
        const FinalEvent(
          tMs: 2,
          segmentId: 's',
          text: caption,
          lang: 'en',
          startMs: 0,
          endMs: 5,
        ),
      );
    await pumpEventQueue();
    if (fail) {
      r.engines.single.out.addError(
        StateError('socket closed while holding $caption'),
      );
      await pumpEventQueue();
    } else {
      await r.controller.stop();
    }
    await r.controller.heartbeat();
    return r;
  }

  test('after a session and an export, the documents directory holds only stats.jsonl (FR-018)', () async {
    final Rig r = await runSession();
    await TranscriptExporter(
      sharer: _OkSharer(),
      tempDir: () async => temp,
    ).export(
      fileName: 'captions.txt',
      body: buildTranscript(
        segments: r.controller.segments,
        startedAt: DateTime(2026),
        duration: const Duration(minutes: 1),
        engineId: 'fake',
        mode: 'auto',
      ),
    );
    final List<String> names = documents
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .toList();
    expect(names, <String>['stats.jsonl']);
    expect(temp.listSync(), isEmpty, reason: 'the export file is removed');
  });

  test('log records contain no caption text and no key (XII, XIII)', () async {
    await runSession();
    await runSession(fail: true);
    expect(
      records,
      isNotEmpty,
      reason: 'the failing session logs something to check',
    );
    for (final LogRecord rec in records) {
      final String all = '${rec.message} ${rec.error} ${rec.stackTrace}';
      expect(all, isNot(contains(caption)), reason: rec.message);
      expect(all, isNot(contains(apiKey)), reason: rec.message);
    }
  });

  test(
    'stats written by a failed session contain no text or key either',
    () async {
      await runSession(fail: true);
      final String written = File('${documents.path}/stats.jsonl')
          .readAsStringSync();
      expect(written, isNot(contains(caption)));
      expect(written, isNot(contains(apiKey)));
    },
  );
}
