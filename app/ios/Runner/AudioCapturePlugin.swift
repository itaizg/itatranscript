import AVFoundation
import Flutter

/// Captures the microphone with Apple voice processing and streams 16 kHz mono s16le 20 ms frames
/// to Dart on `itatranscript/audio` (research R-1, R-5, R-6). Interruptions and route changes
/// arrive on the same channel as `{kind: interruption}` messages (FR-022).
///
/// NOTE: written without Xcode on the authoring machine, so it has not been compiled yet. The
/// logic it relies on (`PcmFramer`, `AudioSessionEventMapper`) is unit-tested.
final class AudioCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AudioCapturePlugin()
    FlutterEventChannel(name: "itatranscript/audio", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
    let control = FlutterMethodChannel(
      name: "itatranscript/audio_control", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: control)
  }

  private let engine = AVAudioEngine()
  private var sink: FlutterEventSink?
  private var framer = PcmFramer()
  private var seq = 0
  private var observers: [NSObjectProtocol] = []

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: FlutterPlugin

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      do {
        try start()
        result(nil)
      } catch {
        result(FlutterError(code: "audio_start", message: "\(error)", details: nil))
      }
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start() throws {
    let session = AVAudioSession.sharedInstance()
    // `.voiceChat` enables the system's echo cancellation and noise suppression. The spike may
    // switch to `.measurement` if it turns out to harm recognition (research R-6).
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    try session.setActive(true)
    try engine.inputNode.setVoiceProcessingEnabled(true)

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    seq = 0
    framer = PcmFramer()
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      self?.handle(buffer: buffer)
    }
    observe(session)
    engine.prepare()
    try engine.start()
  }

  private func handle(buffer: AVAudioPCMBuffer) {
    guard let channels = buffer.floatChannelData else { return }
    let count = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var mono = [Float](repeating: 0, count: count)
    for c in 0..<channelCount {
      let data = channels[c]
      for i in 0..<count { mono[i] += data[i] / Float(channelCount) }
    }
    for frame in framer.push(samples: mono, sampleRate: buffer.format.sampleRate) {
      let message: [String: Any] = [
        "seq": seq, "t_ms": seq * 20, "pcm": FlutterStandardTypedData(bytes: frame),
      ]
      seq += 1
      DispatchQueue.main.async { [weak self] in self?.sink?(message) }
    }
  }

  private func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: interruptions and route changes

  private func observe(_ session: AVAudioSession) {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: session, queue: .main
      ) { [weak self] note in
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
          self?.send(AudioSessionEventMapper.notice(for: .interruptionBegan))
        case .ended:
          let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
          let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(
            .shouldResume)
          if shouldResume { try? self?.engine.start() }
          self?.send(
            AudioSessionEventMapper.notice(for: .interruptionEnded(shouldResume: shouldResume)))
        @unknown default:
          break
        }
      })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
      ) { [weak self] note in
        let raw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
        let reason: AudioSessionChange.Reason
        switch AVAudioSession.RouteChangeReason(rawValue: raw) {
        case .oldDeviceUnavailable: reason = .oldDeviceUnavailable
        case .newDeviceAvailable: reason = .newDeviceAvailable
        default: reason = .other
        }
        self?.send(AudioSessionEventMapper.notice(for: .routeChanged(reason)))
      })
  }

  private func send(_ notice: AudioNotice) {
    if let message = notice.message { sink?(message) }
  }
}
