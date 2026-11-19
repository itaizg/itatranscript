import Foundation

/// Cuts a byte stream of 16 kHz mono s16le audio into exact 20 ms (640-byte) frames.
public struct PcmFramer {
  public static let frameBytes = 640

  private var pending = Data()

  public init() {}

  /// Adds bytes and returns every complete frame; leftovers carry over to the next call.
  public mutating func push(_ data: Data) -> [Data] {
    pending.append(data)
    var frames: [Data] = []
    while pending.count >= Self.frameBytes {
      frames.append(pending.prefix(Self.frameBytes))
      pending = Data(pending.dropFirst(Self.frameBytes))
    }
    return frames
  }

  /// Returns the zero-padded last frame, if any bytes are left over.
  public mutating func flush() -> Data? {
    guard !pending.isEmpty else { return nil }
    defer { pending = Data() }
    return pending + Data(count: Self.frameBytes - pending.count)
  }
}
