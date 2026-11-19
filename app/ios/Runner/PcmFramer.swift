import Foundation

/// Converts float audio at any sample rate to 16 kHz mono s16le, in exact 640-byte (20 ms) frames.
///
/// Samples that do not fill a frame are carried over to the next call, so nothing is lost
/// between buffers. Pure logic: no AVFoundation, so it is unit-tested without a device.
struct PcmFramer {
  static let outputRate = 16_000.0
  static let frameBytes = 640
  static let frameSamples = 320

  private var input: [Float] = []
  private var position = 0.0
  private var rate = 0.0
  private var carry: [Int16] = []

  /// Adds mono float samples recorded at `sampleRate` and returns every complete frame.
  mutating func push(samples: [Float], sampleRate: Double) -> [Data] {
    if sampleRate != rate {
      // The rate changed (route change): start the resampler fresh, keep the carried samples.
      rate = sampleRate
      input.removeAll(keepingCapacity: true)
      position = 0
    }
    input.append(contentsOf: smooth(samples, ratio: sampleRate / Self.outputRate))
    let ratio = sampleRate / Self.outputRate
    while position + 1 < Double(input.count) {
      let index = Int(position)
      let fraction = Float(position - Double(index))
      let value = input[index] * (1 - fraction) + input[index + 1] * fraction
      carry.append(Int16(max(-1, min(1, value)) * 32767))
      position += ratio
    }
    let consumed = min(Int(position), input.count)
    input.removeFirst(consumed)
    position -= Double(consumed)

    var frames: [Data] = []
    while carry.count >= Self.frameSamples {
      let chunk = Array(carry.prefix(Self.frameSamples))
      carry.removeFirst(Self.frameSamples)
      frames.append(chunk.withUnsafeBufferPointer { Data(buffer: $0) })
    }
    return frames
  }

  /// A 3-tap moving average before decimation, to keep high frequencies from folding down.
  private func smooth(_ samples: [Float], ratio: Double) -> [Float] {
    guard ratio >= 2, samples.count > 2 else { return samples }
    var out = samples
    for i in 1..<(samples.count - 1) {
      out[i] = (samples[i - 1] + samples[i] + samples[i + 1]) / 3
    }
    return out
  }
}
