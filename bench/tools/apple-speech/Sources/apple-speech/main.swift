import AVFoundation
import AppleSpeechCore
import Foundation
import Speech

// apple-speech availability | recognize --locale <id> | voiceproc
// stdin: 16 kHz mono s16le PCM. stdout: JSON lines (schema events, or PCM for voiceproc).

setvbuf(stdout, nil, _IOLBF, 0)
let started = DispatchTime.now()

func nowMs() -> Int {
  Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
}
func emit(_ line: String) { print(line) }

func availability(_ locale: String) -> LocaleAvailability {
  guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
    return LocaleAvailability(locale: locale, recognizerAvailable: false, supportsOnDevice: false)
  }
  return LocaleAvailability(
    locale: locale, recognizerAvailable: recognizer.isAvailable,
    supportsOnDevice: recognizer.supportsOnDeviceRecognition)
}

func runAvailability() {
  AvailabilityReport.lines(["he-IL", "en-US"].map(availability)).forEach(emit)
}

// MARK: recognize

final class Recognition {
  private let recognizer: SFSpeechRecognizer
  private let lang: String
  private let queue = DispatchQueue(label: "recognition")
  private var encoder = EventEncoder()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var segment = 0
  private var inputEnded = false
  private let done = DispatchSemaphore(value: 0)
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

  init(recognizer: SFSpeechRecognizer, lang: String) {
    self.recognizer = recognizer
    self.lang = lang
  }

  private func startTask() {
    segment += 1
    let id = "s\(segment)"
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.request = request
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      self?.queue.async { self?.handle(id: id, result: result, error: error) }
    }
  }

  private func handle(id: String, result: SFSpeechRecognitionResult?, error: Error?) {
    if let result {
      let segments = result.bestTranscription.segments
      let start = Int((segments.first?.timestamp ?? 0) * 1000)
      let end = Int(((segments.last?.timestamp ?? 0) + (segments.last?.duration ?? 0)) * 1000)
      let value = RecognitionResult(
        segmentId: id, text: result.bestTranscription.formattedString,
        isFinal: result.isFinal, startMs: start, endMs: end, lang: lang)
      encoder.lines(for: value, tMs: nowMs()).forEach(emit)
      if result.isFinal { finishSegment() }
    } else if let error {
      emit(
        EventEncoder.error(
          code: "internal", message: error.localizedDescription, retryable: false, tMs: nowMs()))
      finishSegment()
    }
  }

  private func finishSegment() {
    if inputEnded {
      emit(EventEncoder.closed(tMs: nowMs()))
      done.signal()
    } else {
      startTask()
    }
  }

  func feed(_ frame: Data) {
    queue.async {
      guard let request = self.request,
        let buffer = AVAudioPCMBuffer(
          pcmFormat: self.format, frameCapacity: AVAudioFrameCount(frame.count / 2))
      else { return }
      buffer.frameLength = buffer.frameCapacity
      frame.withUnsafeBytes { raw in
        if let base = raw.baseAddress { memcpy(buffer.int16ChannelData![0], base, frame.count) }
      }
      request.append(buffer)
    }
  }

  func run() {
    queue.sync { startTask() }
    var framer = PcmFramer()
    while let chunk = try? FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
      framer.push(chunk).forEach(feed)
    }
    if let last = framer.flush() { feed(last) }
    queue.sync {
      inputEnded = true
      request?.endAudio()
    }
    done.wait()
  }
}

func runRecognize(locale: String) {
  let semaphore = DispatchSemaphore(value: 0)
  var status = SFSpeechRecognizerAuthorizationStatus.notDetermined
  SFSpeechRecognizer.requestAuthorization {
    status = $0
    semaphore.signal()
  }
  semaphore.wait()
  guard status == .authorized else {
    emit(
      EventEncoder.error(
        code: "auth", message: "speech recognition not authorized", retryable: false, tMs: nowMs()))
    emit(EventEncoder.closed(tMs: nowMs()))
    return
  }
  let info = availability(locale)
  guard info.usableOnDevice, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
  else {
    emit(
      EventEncoder.error(
        code: "unsupported_language", message: "\(locale) is not available on device",
        retryable: false, tMs: nowMs()))
    emit(EventEncoder.closed(tMs: nowMs()))
    return
  }
  Recognition(recognizer: recognizer, lang: String(locale.prefix(2))).run()
}

// MARK: voiceproc

/// Tries to run PCM through Apple voice processing in manual (offline) rendering mode.
/// Exits 3 with a message when the OS rejects that combination (see lessons.md).
func runVoiceProcessing() {
  let input = FileHandle.standardInput.readDataToEndOfFile()
  let engine = AVAudioEngine()
  do {
    try engine.inputNode.setVoiceProcessingEnabled(true)
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    try engine.start()
    let samples = input.count / 2
    let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples))!
    source.frameLength = source.frameCapacity
    input.withUnsafeBytes { raw in
      let ints = raw.bindMemory(to: Int16.self)
      for i in 0..<samples { source.floatChannelData![0][i] = Float(ints[i]) / 32768 }
    }
    player.scheduleBuffer(source, completionHandler: nil)
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var rendered = 0
    var pcm = Data()
    while rendered < samples {
      let status = try engine.renderOffline(
        AVAudioFrameCount(min(4096, samples - rendered)), to: out)
      guard status == .success else { break }
      for i in 0..<Int(out.frameLength) {
        var v = Int16(max(-1, min(1, out.floatChannelData![0][i])) * 32767)
        pcm.append(Data(bytes: &v, count: 2))
      }
      rendered += Int(out.frameLength)
    }
    FileHandle.standardOutput.write(pcm)
  } catch {
    FileHandle.standardError.write(Data("voiceproc unavailable: \(error)\n".utf8))
    exit(3)
  }
}

/// Fallback when offline rendering rejects voice processing: play the audio out loud and capture
/// it through the voice-processed microphone. Needs speakers, a quiet room and microphone access.
func runLoopback() {
  let input = FileHandle.standardInput.readDataToEndOfFile()
  let engine = AVAudioEngine()
  let lock = NSLock()
  var captured = Data()
  do {
    try engine.inputNode.setVoiceProcessingEnabled(true)
    let play = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let out = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: play)
    let micFormat = engine.inputNode.outputFormat(forBus: 0)
    guard let converter = AVAudioConverter(from: micFormat, to: out) else {
      throw NSError(
        domain: "apple-speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "no converter"])
    }
    engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
      let capacity =
        AVAudioFrameCount(Double(buffer.frameLength) * 16000 / micFormat.sampleRate) + 16
      guard let converted = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity) else {
        return
      }
      var consumed = false
      converter.convert(to: converted, error: nil) { _, status in
        if consumed {
          status.pointee = .noDataNow
          return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
      }
      let bytes = Data(bytes: converted.int16ChannelData![0], count: Int(converted.frameLength) * 2)
      lock.lock()
      captured.append(bytes)
      lock.unlock()
    }
    let samples = input.count / 2
    let source = AVAudioPCMBuffer(pcmFormat: play, frameCapacity: AVAudioFrameCount(samples))!
    source.frameLength = source.frameCapacity
    input.withUnsafeBytes { raw in
      let ints = raw.bindMemory(to: Int16.self)
      for i in 0..<samples { source.floatChannelData![0][i] = Float(ints[i]) / 32768 }
    }
    engine.prepare()
    try engine.start()
    let finished = DispatchSemaphore(value: 0)
    player.scheduleBuffer(source) { finished.signal() }
    player.play()
    finished.wait()
    Thread.sleep(forTimeInterval: 0.5)
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    lock.lock()
    let result = captured
    lock.unlock()
    FileHandle.standardOutput.write(result)
  } catch {
    FileHandle.standardError.write(Data("voiceproc loopback failed: \(error)\n".utf8))
    exit(3)
  }
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "availability": runAvailability()
case "recognize":
  let locale =
    args.firstIndex(of: "--locale").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    ?? "en-US"
  runRecognize(locale: locale)
case "voiceproc":
  if args.contains("--loopback") { runLoopback() } else { runVoiceProcessing() }
default:
  FileHandle.standardError.write(
    Data(
      "usage: apple-speech availability | recognize --locale <id> | voiceproc [--loopback]\n".utf8))
  exit(2)
}
