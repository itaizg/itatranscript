import 'package:flutter/foundation.dart';

import '../models/caption_segment.dart';

/// How the caption list is being viewed. This is view state, separate from the session state:
/// capture continues while frozen.
enum ViewMode {
  /// Showing the newest line; auto-scroll on.
  following,

  /// The visible lines are held still (FR-009).
  frozen,

  /// The user scrolled up; auto-scroll is paused (FR-010).
  scrolledBack,
}

/// Decides which segments the caption screen shows, and whether to auto-scroll.
///
/// It never drops anything: new segments keep arriving in the session, and
/// returning to [ViewMode.following] shows all of them.
class CaptionViewController extends ChangeNotifier {
  ViewMode _mode = ViewMode.following;
  List<CaptionSegment> _frozen = const <CaptionSegment>[];

  /// Current mode.
  ViewMode get mode => _mode;

  /// Whether the list should follow the newest line.
  bool get autoScroll => _mode == ViewMode.following;

  /// Whether to show the "jump to live" chip.
  bool get showJumpToLive => _mode != ViewMode.following;

  /// The segments to render for the current [live] list.
  List<CaptionSegment> visible(List<CaptionSegment> live) =>
      _mode == ViewMode.frozen ? _frozen : live;

  /// Holds the screen still on the [current] lines.
  void freeze(List<CaptionSegment> current) {
    _frozen = List<CaptionSegment>.unmodifiable(current);
    _set(ViewMode.frozen);
  }

  /// Leaves freeze or scroll-back and jumps to the newest line.
  void resume() {
    _frozen = const <CaptionSegment>[];
    _set(ViewMode.following);
  }

  /// The user scrolled away from the bottom.
  void scrolledUp() {
    if (_mode == ViewMode.following) {
      _set(ViewMode.scrolledBack);
    }
  }

  /// The user scrolled back to the bottom.
  void reachedBottom() {
    if (_mode == ViewMode.scrolledBack) {
      _set(ViewMode.following);
    }
  }

  void _set(ViewMode mode) {
    _mode = mode;
    notifyListeners();
  }
}
