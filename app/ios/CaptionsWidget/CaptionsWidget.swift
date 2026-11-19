import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen entry points that run `StartCaptionsIntent` (FR-011, SC-008): a Control Center /
/// Lock Screen control (iOS 18) and an accessory widget.
///
/// NOTE: written without Xcode on the authoring machine. This folder is NOT part of the Xcode
/// project yet: add a Widget Extension target named `CaptionsWidget` in Xcode (File ▸ New ▸
/// Target), include this file and `Runner/StartCaptionsIntent.swift` in it, then build.
@available(iOS 18.0, *)
struct StartCaptionsControl: ControlWidget {
  static let kind = "dev.itai.itatranscript.StartCaptions"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: StartCaptionsIntent()) {
        Label("Start captions", systemImage: "captions.bubble")
      }
    }
    .displayName("Start captions")
    .description("Opens Itatranscript and starts live captions.")
  }
}

struct StartCaptionsEntry: TimelineEntry {
  let date: Date
}

struct StartCaptionsProvider: TimelineProvider {
  func placeholder(in context: Context) -> StartCaptionsEntry { StartCaptionsEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (StartCaptionsEntry) -> Void) {
    completion(StartCaptionsEntry(date: .now))
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<StartCaptionsEntry>) -> Void
  ) {
    completion(Timeline(entries: [StartCaptionsEntry(date: .now)], policy: .never))
  }
}

@available(iOS 17.0, *)
struct StartCaptionsLockScreenWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "dev.itai.itatranscript.LockScreen", provider: StartCaptionsProvider()
    ) { _ in
      Button(intent: StartCaptionsIntent()) {
        Image(systemName: "captions.bubble")
      }
      .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Start captions")
    .description("One tap to start live captions.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

@main
struct CaptionsWidgetBundle: WidgetBundle {
  var body: some Widget {
    StartCaptionsLockScreenWidget()
    if #available(iOS 18.0, *) { StartCaptionsControl() }
  }
}
