import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/export/transcript_export.dart';
import 'package:itatranscript/models/caption_segment.dart';

CaptionSegment _s(
  String text,
  int startMs, {
  String lang = 'en',
  SegmentStatus status = SegmentStatus.finalized,
  bool change = false,
  EngineRole role = EngineRole.active,
}) => CaptionSegment(
  id: 'x:$startMs',
  status: status,
  text: text,
  lang: lang,
  startMs: startMs,
  endMs: startMs + 100,
  speakerChangeBefore: change,
  engineRole: role,
);

class _Sharer implements Sharer {
  _Sharer({this.fail = false});
  final bool fail;
  String? seenContent;
  String? seenPath;

  @override
  Future<void> share(String path) async {
    seenPath = path;
    seenContent = File(path).readAsStringSync();
    if (fail) {
      throw StateError('share sheet crashed');
    }
  }
}

void main() {
  final DateTime started = DateTime(2026, 12, 1, 19, 2);

  test('the format matches contracts/export-format.md', () {
    final String text = buildTranscript(
      segments: <CaptionSegment>[
        _s('שלום, מה נשמע?', 4000, lang: 'he'),
        _s('Fine thanks, ואיתך?', 7000, lang: 'mixed', change: true),
        _s('fallback line', 1203000, role: EngineRole.fallback),
        _s('', 1205000, lang: 'unknown'),
      ],
      startedAt: started,
      duration: const Duration(hours: 1, minutes: 30),
      engineId: 'google-stt-he',
      mode: 'auto',
    );
    expect(
      text,
      '# Captions – 2026-12-01 19:02 (1h 30m) · engine: google-stt-he · mode: auto\n'
      '\n'
      '[00:00:04] שלום, מה נשמע?\n'
      '[00:00:07] — speaker change —\n'
      '[00:00:07] Fine thanks, ואיתך?\n'
      '[00:20:03] (offline – lower accuracy)\n'
      '[00:20:03] fallback line\n'
      '[00:20:05] [unrecognized]\n',
    );
  });

  test('provisional text is never exported', () {
    final String text = buildTranscript(
      segments: <CaptionSegment>[
        _s('final one', 0),
        _s('still guessing', 5000, status: SegmentStatus.provisional),
      ],
      startedAt: started,
      duration: const Duration(minutes: 5),
      engineId: 'e',
      mode: 'en',
    );
    expect(text, contains('final one'));
    expect(text, isNot(contains('still guessing')));
  });

  test('stats are appended only when test mode passes them in', () {
    String build(Map<String, Object?>? stats) => buildTranscript(
      segments: <CaptionSegment>[_s('x', 0)],
      startedAt: started,
      duration: const Duration(minutes: 1),
      engineId: 'e',
      mode: 'en',
      statsWhenTestMode: stats,
    );
    expect(build(null), isNot(contains('session stats')));
    expect(
      build(<String, Object?>{'v': 1}),
      endsWith('--- session stats ---\n{"v":1}\n'),
    );
  });

  test('the file name is captions-YYYY-MM-DD-HHmm.txt', () {
    expect(exportFileName(started), 'captions-2026-12-01-1902.txt');
  });

  test('the temp file is shared and then deleted', () async {
    final Directory dir = Directory.systemTemp.createTempSync('export_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final _Sharer sharer = _Sharer();
    await TranscriptExporter(
      sharer: sharer,
      tempDir: () async => dir,
    ).export(fileName: 'a.txt', body: 'hello');
    expect(sharer.seenContent, 'hello');
    expect(dir.listSync(), isEmpty);
  });

  test('when sharing fails the user sees a failure and the temp file is still removed', () async {
    final Directory dir = Directory.systemTemp.createTempSync('export_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final TranscriptExporter exporter = TranscriptExporter(
      sharer: _Sharer(fail: true),
      tempDir: () async => dir,
    );
    await expectLater(
      exporter.export(fileName: 'a.txt', body: 'hello'),
      throwsA(isA<ExportFailure>()),
    );
    expect(dir.listSync(), isEmpty);
  });
}
