import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/caption_segment.dart';
import 'package:itatranscript/ui/caption_view_controller.dart';

CaptionSegment _seg(int i) => CaptionSegment(
  id: 'a:$i',
  status: SegmentStatus.finalized,
  text: 'line $i',
  lang: 'en',
  startMs: i * 1000,
  endMs: i * 1000 + 500,
);

List<CaptionSegment> _segs(int n) => <CaptionSegment>[
  for (int i = 0; i < n; i++) _seg(i),
];

void main() {
  test('freeze keeps the visible lines fixed while 20 new segments arrive; resume jumps to the newest', () {
    final CaptionViewController c = CaptionViewController();
    final List<CaptionSegment> live = _segs(5);
    c.freeze(live);
    expect(c.mode, ViewMode.frozen);
    final List<CaptionSegment> grown = <CaptionSegment>[
      ...live,
      ..._segs(25).skip(5),
    ];
    expect(grown, hasLength(25));
    expect(c.visible(grown), hasLength(5), reason: 'the screen stays still');
    expect(c.visible(grown).last.text, 'line 4');
    c.resume();
    expect(c.mode, ViewMode.following);
    expect(
      c.visible(grown),
      hasLength(25),
      reason: 'no segment was lost while frozen',
    );
    expect(c.visible(grown).last.text, 'line 24');
  });

  test('scrolling back pauses auto-scroll and shows the jump chip; reaching the bottom resumes', () {
    final CaptionViewController c = CaptionViewController();
    expect(c.autoScroll, isTrue);
    c.scrolledUp();
    expect(c.mode, ViewMode.scrolledBack);
    expect(c.autoScroll, isFalse);
    expect(c.showJumpToLive, isTrue);
    c.reachedBottom();
    expect(c.mode, ViewMode.following);
    expect(c.showJumpToLive, isFalse);
  });

  test(
    'scrolling does not unfreeze, and reaching the bottom does not unfreeze',
    () {
      final CaptionViewController c = CaptionViewController()..freeze(_segs(3));
      c
        ..scrolledUp()
        ..reachedBottom();
      expect(c.mode, ViewMode.frozen);
    },
  );

  test('the frozen list cannot be changed from outside', () {
    final CaptionViewController c = CaptionViewController()..freeze(_segs(3));
    expect(() => c.visible(_segs(3)).add(_seg(9)), throwsUnsupportedError);
  });

  test('listeners are told about each change', () {
    final CaptionViewController c = CaptionViewController();
    int calls = 0;
    c.addListener(() => calls++);
    c
      ..freeze(_segs(1))
      ..resume();
    expect(calls, 2);
  });
}
