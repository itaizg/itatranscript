import Foundation

/// One recognizer callback, reduced to what the schema needs.
public struct RecognitionResult: Equatable, Sendable {
  public let segmentId: String
  public let text: String
  public let isFinal: Bool
  public let startMs: Int
  public let endMs: Int
  public let lang: String

  public init(
    segmentId: String, text: String, isFinal: Bool, startMs: Int, endMs: Int, lang: String
  ) {
    self.segmentId = segmentId
    self.text = text
    self.isFinal = isFinal
    self.startMs = startMs
    self.endMs = endMs
    self.lang = lang
  }
}

/// Turns recognition results into `shared/engine-events.schema.json` lines.
///
/// Rules: a partial replaces the earlier one; an empty result produces nothing; exactly one
/// final per segment, and nothing follows a final for the same segment.
public struct EventEncoder {
  private var finalised = Set<String>()

  public init() {}

  public mutating func lines(for result: RecognitionResult, tMs: Int) -> [String] {
    guard !finalised.contains(result.segmentId) else { return [] }
    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    var event: [String: Any] = [
      "t_ms": tMs,
      "segment_id": result.segmentId,
      "text": text,
      "lang": result.lang,
      "start_ms": result.startMs,
    ]
    if result.isFinal {
      finalised.insert(result.segmentId)
      event["type"] = "final"
      event["end_ms"] = result.endMs
    } else {
      event["type"] = "partial"
    }
    return [Self.json(event)]
  }

  public static func health(state: String, reason: String, tMs: Int) -> String {
    json(["type": "health", "t_ms": tMs, "state": state, "reason": reason])
  }

  public static func error(code: String, message: String, retryable: Bool, tMs: Int) -> String {
    json(["type": "error", "t_ms": tMs, "code": code, "message": message, "retryable": retryable])
  }

  public static func closed(tMs: Int) -> String {
    json(["type": "closed", "t_ms": tMs])
  }

  static func json(_ object: [String: Any]) -> String {
    let data = try? JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data ?? Data(), as: UTF8.self)
  }
}
