import Foundation
import XCTest

@testable import AppleSpeechCore

final class EventEncoderTests: XCTestCase {
  private func result(_ id: String, _ text: String, final: Bool, end: Int = 1000)
    -> RecognitionResult
  {
    RecognitionResult(segmentId: id, text: text, isFinal: final, startMs: 0, endMs: end, lang: "en")
  }

  private func object(_ line: String) throws -> NSDictionary {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? NSDictionary)
  }

  private func fixtureLines(_ name: String) throws -> [String] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: name, withExtension: "events.jsonl", subdirectory: "native"))
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  func testPartialThenFinalForTheSameSegmentMatchesTheFixture() throws {
    var encoder = EventEncoder()
    var lines: [String] = []
    lines += encoder.lines(for: result("s1", "hel", final: false), tMs: 400)
    lines += encoder.lines(for: result("s1", "hello wor", final: false), tMs: 700)
    lines += encoder.lines(for: result("s1", "hello world", final: true), tMs: 1200)
    lines.append(EventEncoder.closed(tMs: 1300))
    let expected = try fixtureLines("apple-partial-then-final")
    XCTAssertEqual(try lines.map(object), try expected.map(object))
  }

  func testEmptyResultGivesNoFinal() {
    var encoder = EventEncoder()
    XCTAssertTrue(encoder.lines(for: result("s1", "   ", final: true), tMs: 10).isEmpty)
  }

  func testNothingFollowsAFinalForThatSegment() {
    var encoder = EventEncoder()
    XCTAssertEqual(encoder.lines(for: result("s1", "done", final: true), tMs: 10).count, 1)
    XCTAssertTrue(encoder.lines(for: result("s1", "done again", final: true), tMs: 20).isEmpty)
    XCTAssertTrue(encoder.lines(for: result("s1", "late", final: false), tMs: 30).isEmpty)
  }

  func testUnavailableHebrewIsReportedAsNotOnDevice() throws {
    let lines = AvailabilityReport.lines([
      LocaleAvailability(locale: "he-IL", recognizerAvailable: true, supportsOnDevice: false),
      LocaleAvailability(locale: "en-US", recognizerAvailable: true, supportsOnDevice: true),
    ])
    let objects = try lines.map(object)
    XCTAssertEqual(objects[0]["on_device"] as? Bool, false)
    XCTAssertEqual(objects[1]["on_device"] as? Bool, true)
  }

  func testErrorEventCarriesCodeAndRetryable() throws {
    let line = EventEncoder.error(
      code: "unsupported_language", message: "he-IL", retryable: false, tMs: 5)
    let dict = try object(line)
    XCTAssertEqual(dict["code"] as? String, "unsupported_language")
    XCTAssertEqual(dict["retryable"] as? Bool, false)
  }
}
