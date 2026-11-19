import AVFoundation
import Flutter
import Speech

/// On-device Apple recognition for the Dart `AppleSpeechAdapter` (profile `apple-ondevice`).
/// Commands arrive on `itatranscript/apple_speech`; schema events leave on
/// `itatranscript/apple_speech_events`.
///
/// NOTE: written without Xcode on the authoring machine, so it has not been compiled yet. The
/// result-to-event logic lives in `SpeechResultMapper`, which is unit-tested.
final class AppleSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AppleSpeechPlugin()
    FlutterEventChannel(
      name: "itatranscript/apple_speech_events", binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance)
    let control = FlutterMethodChannel(
      name: "itatranscript/apple_speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: control)
  }

  private var sink: FlutterEventSink?
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var mapper = SpeechResultMapper()
  private var locale = "en-US"
  private var segment = 0
  private var inputEnded = false
  private let started = DispatchTime.now()
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

  private var nowMs: Int {
    Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
  }

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

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      let args = call.arguments as? [String: Any]
      open(locale: (args?["locale"] as? String) ?? "en-US")
      result(nil)
    case "push":
      if let args = call.arguments as? [String: Any],
        let data = args["pcm"] as? FlutterStandardTypedData
      {
        push(data.data)
      }
      result(nil)
    case "finish":
      inputEnded = true
      request?.endAudio()
      result(nil)
    case "cancel":
      task?.cancel()
      request = nil
      emit([SpeechResultMapper.closed(tMs: nowMs)])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ events: [[String: Any]]) {
    DispatchQueue.main.async { [weak self] in
      for event in events { self?.sink?(event) }
    }
  }

  private func open(locale: String) {
    self.locale = locale
    mapper = SpeechResultMapper()
    inputEnded = false
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      guard let self else { return }
      guard status == .authorized else {
        self.emit([
          [
            "type": "error", "t_ms": self.nowMs, "code": "auth",
            "message": "speech recognition not authorized", "retryable": false,
          ],
          SpeechResultMapper.closed(tMs: self.nowMs),
        ])
        return
      }
      guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
        recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
      else {
        self.emit(SpeechResultMapper.unsupportedLanguage(locale: locale, tMs: self.nowMs))
        return
      }
      self.recognizer = recognizer
      self.startTask()
    }
  }

  private func startTask() {
    segment += 1
    let id = "s\(segment)"
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.request = request
    task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let segments = result.bestTranscription.segments
        let value = SpeechResult(
          segmentId: id, text: result.bestTranscription.formattedString, isFinal: result.isFinal,
          startMs: Int((segments.first?.timestamp ?? 0) * 1000),
          endMs: Int(((segments.last?.timestamp ?? 0) + (segments.last?.duration ?? 0)) * 1000),
          lang: String(self.locale.prefix(2)))
        self.emit(self.mapper.events(for: value, tMs: self.nowMs))
        if result.isFinal { self.finishSegment() }
      } else if error != nil {
        self.emit([
          [
            "type": "error", "t_ms": self.nowMs, "code": "internal",
            "message": "recognition failed", "retryable": false,
          ]
        ])
        self.finishSegment()
      }
    }
  }

  private func finishSegment() {
    if inputEnded {
      emit([SpeechResultMapper.closed(tMs: nowMs)])
    } else {
      startTask()
    }
  }

  private func push(_ pcm: Data) {
    guard let request,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count / 2))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    pcm.withUnsafeBytes { raw in
      if let base = raw.baseAddress, let target = buffer.int16ChannelData?[0] {
        memcpy(target, base, pcm.count)
      }
    }
    request.append(buffer)
  }
}
