// swift-tools-version: 6.0
import PackageDescription

// AppKit and callback-heavy system APIs are easier to work with in Swift 5 mode.
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "shades",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shades", targets: ["Shades"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2"),
    ],
    targets: [
        // Shared types, contracts and prompts. No UI and no system capture.
        .target(name: "ShadesCore", swiftSettings: settings),
        // Talks to the local T3 Code server.
        .target(name: "ShadesT3", dependencies: ["ShadesCore"], swiftSettings: settings),
        // Sees the screen: capture, selected text, browser page.
        .target(name: "ShadesContext", dependencies: ["ShadesCore"], swiftSettings: settings),
        // Hears you: microphone, on-device speech, cleanup, text insertion.
        .target(
            name: "ShadesVoice",
            dependencies: ["ShadesCore", .product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: settings
        ),
        // The cat itself, and the app that wires everything together.
        .executableTarget(
            name: "Shades",
            dependencies: ["ShadesCore", "ShadesT3", "ShadesContext", "ShadesVoice"],
            swiftSettings: settings
        ),

        // Small command-line tools for trying one module without the app.
        .executableTarget(name: "probe-t3", dependencies: ["ShadesCore", "ShadesT3"], path: "Sources/Probes/T3", swiftSettings: settings),
        .executableTarget(name: "probe-context", dependencies: ["ShadesCore", "ShadesContext"], path: "Sources/Probes/Context", swiftSettings: settings),
        .executableTarget(name: "probe-voice", dependencies: ["ShadesCore", "ShadesVoice"], path: "Sources/Probes/Voice", swiftSettings: settings),

        .testTarget(name: "ShadesCoreTests", dependencies: ["ShadesCore"], swiftSettings: settings),
        .testTarget(name: "ShadesT3Tests", dependencies: ["ShadesT3"], swiftSettings: settings),
        .testTarget(name: "ShadesContextTests", dependencies: ["ShadesContext"], swiftSettings: settings),
        .testTarget(name: "ShadesVoiceTests", dependencies: ["ShadesVoice"], swiftSettings: settings),
        .testTarget(name: "ShadesTests", dependencies: ["Shades"], swiftSettings: settings),
    ]
)
