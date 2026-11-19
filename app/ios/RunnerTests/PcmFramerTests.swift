import XCTest

@testable import Runner

final class PcmFramerTests: XCTestCase {
  private func sine(frequency: Double, rate: Double, seconds: Double) -> [Float] {
    (0..<Int(rate * seconds)).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) * 0.8 }
  }

  private func samples(_ frames: [Data]) -> [Int16] {
    frames.flatMap { frame in
      frame.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }
  }

  func testFrameSizeIsAlways640() {
    var framer = PcmFramer()
    let frames = framer.push(
      samples: sine(frequency: 440, rate: 48_000, seconds: 1), sampleRate: 48_000)
    XCTAssertFalse(frames.isEmpty)
    XCTAssertTrue(frames.allSatisfy { $0.count == 640 })
  }

  func testA48kHzSineKeepsItsFrequencyWithinOnePercent() {
    var framer = PcmFramer()
    let frames = framer.push(
      samples: sine(frequency: 440, rate: 48_000, seconds: 2), sampleRate: 48_000)
    let out = samples(frames)
    var crossings = 0
    for i in 1..<out.count where out[i - 1] < 0 && out[i] >= 0 { crossings += 1 }
    let seconds = Double(out.count) / 16_000
    let measured = Double(crossings) / seconds
    XCTAssertEqual(measured, 440, accuracy: 4.4)
  }

  func testOddBufferSizesLoseNoSamples() {
    var framer = PcmFramer()
    let all = sine(frequency: 300, rate: 48_000, seconds: 1.5)
    var frames: [Data] = []
    var index = 0
    for size in [1, 479, 480, 481, 1_001, 4_097, 333] where index < all.count {
      let end = min(index + size, all.count)
      frames += framer.push(samples: Array(all[index..<end]), sampleRate: 48_000)
      index = end
    }
    frames += framer.push(samples: Array(all[index...]), sampleRate: 48_000)
    let expected = Double(all.count) / 3
    XCTAssertEqual(Double(samples(frames).count), expected, accuracy: 320 + 4)
  }

  func testSameRateInputPassesThroughUnchanged() {
    var framer = PcmFramer()
    let input = sine(frequency: 500, rate: 16_000, seconds: 0.5)
    let out = samples(framer.push(samples: input, sampleRate: 16_000))
    XCTAssertEqual(out.count, (input.count - 1) / 320 * 320)
  }
}
