import Foundation
import XCTest

@testable import AppleSpeechCore

final class PcmFramerTests: XCTestCase {
  func testOddChunkSizesLoseNoBytesAndFramesAreAlways640() {
    var framer = PcmFramer()
    var frames: [Data] = []
    let sizes = [1, 639, 640, 641, 1500, 7]
    for size in sizes {
      frames += framer.push(Data(repeating: 7, count: size))
    }
    let total = sizes.reduce(0, +)
    XCTAssertTrue(frames.allSatisfy { $0.count == 640 })
    XCTAssertEqual(frames.count, total / 640)
    XCTAssertEqual(framer.flush()?.count, 640)
    XCTAssertNil(framer.flush())
  }

  func testFlushOnEmptyReturnsNil() {
    var framer = PcmFramer()
    XCTAssertNil(framer.flush())
  }
}
