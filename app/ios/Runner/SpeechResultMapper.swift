import Foundation

/// One recognizer callback, reduced to what the schema needs.
struct SpeechResult: Equatable {
  let segmentId: String
  let text: String
  let isFinal: Bool
  let startMs: Int
  let endMs: Int
  let lang: String
}

/// Turns recognition results into `shared/engine-events.schema.json` events for the channel.
///
/// This is a small, deliberate copy of `AppleSpeechCore.EventEncoder` from the Mac helper: the app
/// may not depend on the harness (constitution VI), and two copies are accepted until a third appears.
/// Rules: a partial replaces the earlier one; an empty result produces nothing; exactly one final
/// per segment; nothing follows a final.
struct SpeechResultMapper {
  private var finalised = Set<String>()

  mutating func events(for result: SpeechResult, tMs: Int) -> [[String: Any]] {
    guard !finalised.contains(result.segmentId) else { return [] }
    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    var event: [String: Any] = [
      "t_ms": tMs, "segment_id": result.segmentId, "text": text,
      "lang": result.lang, "start_ms": result.startMs,
    ]
    if result.isFinal {
      finalised.insert(result.segmentId)
      event["type"] = "final"
      event["end_ms"] = result.endMs
    } else {
      event["type"] = "partial"
    }
    return [event]
  }

  /// `he-IL` (or any locale) cannot run on the device.
  static func unsupportedLanguage(locale: String, tMs: Int) -> [[String: Any]] {
    [
      [
        "type": "error", "t_ms": tMs, "code": "unsupported_language",
        "message": "\(locale) is not available on device", "retryable": false,
      ],
      ["type": "closed", "t_ms": tMs],
    ]
  }

  static func closed(tMs: Int) -> [String: Any] { ["type": "closed", "t_ms": tMs] }
}
