import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/fake_engine.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:itatranscript/session/caption_assembler.dart';

import 'support.dart';

CaptionAssembler _run(String fixture) {
  final CaptionAssembler a = CaptionAssembler();
  parseEventLog(readShared('fixtures/$fixture')).forEach(a.apply);
  return a;
}

void main() {
  test('partial then final gives one final segment, no duplicate', () {
    final List<CaptionSegment> s = _run('partial-then-final.events.jsonl')
        .segments;
    expect(s, hasLength(1));
    expect(s.single.status, SegmentStatus.finalized);
    expect(s.single.text, 'hello world');
  });

  test('a final is never changed by later events for the same id', () {
    final CaptionAssembler a = _run('partial-then-final.events.jsonl');
    expect(
      a.apply(
        const PartialEvent(
          tMs: 2000,
          segmentId: 's1',
          text: 'late',
          startMs: 0,
        ),
      ),
      isFalse,
    );
    expect(
      a.apply(
        const FinalEvent(
          tMs: 2100,
          segmentId: 's1',
          text: 'changed',
          lang: 'en',
          startMs: 0,
          endMs: 1,
        ),
      ),
      isFalse,
    );
    expect(a.segments.single.text, 'hello world');
  });

  test('a speaker change marks the next new segment only', () {
    final List<CaptionSegment> s = _run('speaker-change.events.jsonl').segments;
    expect(s.map((CaptionSegment x) => x.speakerChangeBefore), <bool>[
      false,
      true,
    ]);
  });

  test('a partial without a language is unrecognized', () {
    final CaptionAssembler a = CaptionAssembler()
      ..apply(
        const PartialEvent(tMs: 1, segmentId: 'x', text: '???', startMs: 0),
      );
    expect(a.segments.single.isUnrecognized, isTrue);
  });

  test('the returned list cannot be modified', () {
    final CaptionAssembler a = _run('partial-then-final.events.jsonl');
    expect(() => a.segments.clear(), throwsUnsupportedError);
  });

  test('dropProvisional removes only that namespace\'s open text', () {
    final CaptionAssembler a = CaptionAssembler()
      ..apply(
        const PartialEvent(tMs: 1, segmentId: 'p', text: 'open', startMs: 0),
        namespace: 'old',
      )
      ..apply(
        const FinalEvent(
          tMs: 2,
          segmentId: 'f',
          text: 'done',
          lang: 'en',
          startMs: 0,
          endMs: 1,
        ),
        namespace: 'old',
      )
      ..dropProvisional('old');
    expect(a.segments.map((CaptionSegment s) => s.text), <String>['done']);
  });
}
