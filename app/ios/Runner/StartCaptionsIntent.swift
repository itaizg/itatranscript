import AppIntents

/// Starts captions from the Lock Screen control, a Shortcut or a widget (FR-011, research R-9).
///
/// The intent only records the request and opens the app; `AppDelegate` hands it to Dart, which
/// starts the session. One tap plus Face ID is within the 2-tap budget.
///
/// NOTE: written without Xcode on the authoring machine, so it has not been compiled yet.
@available(iOS 17.0, *)
struct StartCaptionsIntent: AppIntent {
  static let title: LocalizedStringResource = "Start captions"
  static let description = IntentDescription("Opens Itatranscript and starts live captions.")
  static let openAppWhenRun = true

  static let requestKey = "itatranscript.startRequested"

  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set(true, forKey: Self.requestKey)
    return .result()
  }
}
