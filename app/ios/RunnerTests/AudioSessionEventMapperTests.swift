import XCTest

@testable import Runner

final class AudioSessionEventMapperTests: XCTestCase {
  func testInterruptionBeganPausesTheMic() {
    XCTAssertEqual(
      AudioSessionEventMapper.notice(for: .interruptionBegan),
      .pausedMic(reason: "phone call or another app"))
  }

  func testInterruptionEndedWithShouldResumeResumes() {
    XCTAssertEqual(
      AudioSessionEventMapper.notice(for: .interruptionEnded(shouldResume: true)), .resume)
  }

  func testInterruptionEndedWithoutShouldResumeDoesNothing() {
    XCTAssertEqual(
      AudioSessionEventMapper.notice(for: .interruptionEnded(shouldResume: false)), .none)
  }

  func testRouteChanges() {
    XCTAssertEqual(
      AudioSessionEventMapper.notice(for: .routeChanged(.oldDeviceUnavailable)),
      .pausedMic(reason: "microphone disconnected"))
    XCTAssertEqual(AudioSessionEventMapper.notice(for: .routeChanged(.newDeviceAvailable)), .resume)
    XCTAssertEqual(AudioSessionEventMapper.notice(for: .routeChanged(.other)), .none)
  }

  func testNoticeMessagesMatchWhatDartExpects() {
    let paused = AudioNotice.pausedMic(reason: "x").message
    XCTAssertEqual(paused?["kind"] as? String, "interruption")
    XCTAssertEqual(paused?["paused"] as? Bool, true)
    XCTAssertEqual(AudioNotice.resume.message?["paused"] as? Bool, false)
    XCTAssertNil(AudioNotice.none.message)
  }
}
