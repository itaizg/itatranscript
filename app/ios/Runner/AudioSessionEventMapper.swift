import Foundation

/// What happened to the audio session, reduced to the facts the decision needs.
enum AudioSessionChange: Equatable {
  case interruptionBegan
  case interruptionEnded(shouldResume: Bool)
  case routeChanged(Reason)

  enum Reason: Equatable {
    case oldDeviceUnavailable
    case newDeviceAvailable
    case other
  }
}

/// What to tell Dart (`paused_mic` / resume / nothing).
enum AudioNotice: Equatable {
  case pausedMic(reason: String)
  case resume
  case none

  /// The message sent on the audio event channel.
  var message: [String: Any]? {
    switch self {
    case .pausedMic(let reason):
      return ["kind": "interruption", "paused": true, "reason": reason]
    case .resume:
      return ["kind": "interruption", "paused": false, "reason": "resumed"]
    case .none:
      return nil
    }
  }
}

/// Decides what an `AVAudioSession` notification means for the captions (FR-022). Pure logic.
enum AudioSessionEventMapper {
  static func notice(for change: AudioSessionChange) -> AudioNotice {
    switch change {
    case .interruptionBegan:
      return .pausedMic(reason: "phone call or another app")
    case .interruptionEnded(let shouldResume):
      return shouldResume ? .resume : .none
    case .routeChanged(let reason):
      switch reason {
      case .oldDeviceUnavailable: return .pausedMic(reason: "microphone disconnected")
      case .newDeviceAvailable: return .resume
      case .other: return .none
      }
    }
  }
}
