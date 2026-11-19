// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "apple-speech",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "apple-speech", targets: ["apple-speech"]),
    .library(name: "AppleSpeechCore", targets: ["AppleSpeechCore"]),
  ],
  targets: [
    // Pure logic: no Speech or AVFoundation calls, so it is fully unit-testable.
    .target(name: "AppleSpeechCore"),
    .executableTarget(
      name: "apple-speech",
      dependencies: ["AppleSpeechCore"],
      exclude: ["Info.plist"],
      swiftSettings: [.swiftLanguageMode(.v5)],
      // Embeds the usage strings that macOS requires before it will ask for permission.
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist", "-Xlinker", "Sources/apple-speech/Info.plist",
        ])
      ]
    ),
    .testTarget(
      name: "AppleSpeechCoreTests",
      dependencies: ["AppleSpeechCore"],
      resources: [.copy("native")]
    ),
  ]
)
