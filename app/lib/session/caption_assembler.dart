import '../models/caption_segment.dart';
import '../models/engine_event.dart';

/// Turns engine events into an ordered list of caption segments.
///
/// A final is never changed. A partial replaces the earlier partial with the same id.
/// A speaker change marks the next new segment.
class CaptionAssembler {
  final Map<String, CaptionSegment> _byId = <String, CaptionSegment>{};
  final List<String> _order = <String>[];
  bool _speakerChangePending = false;

  /// Segments in the order they started; the list cannot be modified.
  List<CaptionSegment> get segments =>
      List<CaptionSegment>.unmodifiable(_order.map((String id) => _byId[id]!));

  /// Applies one event. [namespace] keeps ids from different adapter instances apart.
  /// Returns true when the visible segments changed.
  bool apply(
    EngineEvent event, {
    String namespace = 'a',
    EngineRole role = EngineRole.active,
  }) {
    switch (event) {
      case SpeakerChangeEvent():
        _speakerChangePending = true;
        return false;
      case PartialEvent():
        return _put(
          '$namespace:${event.segmentId}',
          SegmentStatus.provisional,
          event.text,
          event.lang ?? 'unknown',
          event.startMs,
          event.endMs ?? event.startMs,
          role,
        );
      case FinalEvent():
        return _put(
          '$namespace:${event.segmentId}',
          SegmentStatus.finalized,
          event.text,
          event.lang,
          event.startMs,
          event.endMs,
          role,
        );
      case HealthEvent() || UsageEvent() || ErrorEvent() || ClosedEvent():
        return false;
    }
  }

  bool _put(
    String id,
    SegmentStatus status,
    String text,
    String lang,
    int startMs,
    int endMs,
    EngineRole role,
  ) {
    final CaptionSegment? existing = _byId[id];
    if (existing == null) {
      _byId[id] = CaptionSegment(
        id: id,
        status: status,
        text: text,
        lang: lang,
        startMs: startMs,
        endMs: endMs,
        speakerChangeBefore: _speakerChangePending,
        engineRole: role,
      );
      _order.add(id);
      _speakerChangePending = false;
      return true;
    }
    if (existing.status == SegmentStatus.finalized) {
      return false;
    }
    _byId[id] = existing.copyWith(
      status: status,
      text: text,
      lang: lang,
      endMs: endMs,
    );
    return true;
  }

  /// Drops every provisional segment (an engine switch makes open text stale).
  void dropAllProvisional() => _drop((String id) => true);

  /// Drops provisional segments of [namespace] (an engine was lost; its open text is stale).
  void dropProvisional(String namespace) =>
      _drop((String id) => id.startsWith('$namespace:'));

  void _drop(bool Function(String id) matches) {
    final List<String> stale = _order
        .where(
          (String id) =>
              matches(id) && _byId[id]!.status == SegmentStatus.provisional,
        )
        .toList();
    for (final String id in stale) {
      _byId.remove(id);
      _order.remove(id);
    }
  }
}
