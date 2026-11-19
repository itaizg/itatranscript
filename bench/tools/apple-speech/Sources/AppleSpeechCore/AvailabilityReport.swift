import Foundation

/// Whether on-device recognition works for one locale (research R-17).
public struct LocaleAvailability: Equatable, Sendable {
  public let locale: String
  public let recognizerAvailable: Bool
  public let supportsOnDevice: Bool

  public init(locale: String, recognizerAvailable: Bool, supportsOnDevice: Bool) {
    self.locale = locale
    self.recognizerAvailable = recognizerAvailable
    self.supportsOnDevice = supportsOnDevice
  }

  /// True only when the recognizer exists and can run without the network.
  public var usableOnDevice: Bool { recognizerAvailable && supportsOnDevice }
}

public enum AvailabilityReport {
  /// One JSON object per locale, e.g. `{"locale":"he-IL","on_device":false}`.
  public static func lines(_ entries: [LocaleAvailability]) -> [String] {
    entries.map {
      EventEncoder.json([
        "locale": $0.locale,
        "recognizer_available": $0.recognizerAvailable,
        "on_device": $0.usableOnDevice,
      ])
    }
  }
}
