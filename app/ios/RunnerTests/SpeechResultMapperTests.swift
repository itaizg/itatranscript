import XCTest

@testable import Runner

final class SpeechResultMapperTests: XCTestCase {
  private func result(_ text: String, final: Bool) -> SpeechResult {
    SpeechResult(segmentId: "s1", text: text, isFinal: final, startMs: 0, endMs: 1000, lang: "en")
  }

  /// `shared/fixtures/native/*.events.jsonl`, found relative to this file.
  private func fixture(_ name: String) throws -> [NSDictionary] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("shared/fixtures/native/\(name).events.jsonl")
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text.split(separator: "\n").map {
      try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? NSDictionary)
    }
  }

  func testPartialThenFinalMatchesTheSharedFixture() throws {
    var mapper = SpeechResultMapper()
    var events: [[String: Any]] = []
    events += mapper.events(for: result("hel", final: false), tMs: 400)
    events += mapper.events(for: result("hello wor", final: false), tMs: 700)
    events += mapper.events(for: result("hello world", final: true), tMs: 1200)
    events.append(SpeechResultMapper.closed(tMs: 1300))
    XCTAssertEqual(events.map { $0 as NSDictionary }, try fixture("apple-partial-then-final"))
  }

  func testAnEmptyResultGivesNoFinal() {
    var mapper = SpeechResultMapper()
    XCTAssertTrue(mapper.events(for: result("  ", final: true), tMs: 5).isEmpty)
  }

  func testNothingFollowsAFinalForThatSegment() {
    var mapper = SpeechResultMapper()
    XCTAssertEqual(mapper.events(for: result("done", final: true), tMs: 1).count, 1)
    XCTAssertTrue(mapper.events(for: result("again", final: true), tMs: 2).isEmpty)
    XCTAssertTrue(mapper.events(for: result("late", final: false), tMs: 3).isEmpty)
  }

  func testHebrewUnavailableGivesUnsupportedLanguage() {
    let events = SpeechResultMapper.unsupportedLanguage(locale: "he-IL", tMs: 9)
    XCTAssertEqual(events[0]["code"] as? String, "unsupported_language")
    XCTAssertEqual(events[0]["retryable"] as? Bool, false)
    XCTAssertEqual(events[1]["type"] as? String, "closed")
  }
}
