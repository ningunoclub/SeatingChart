// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Swift 5 language mode: the store is a plain main-thread @Observable object.
// Tools version 6 is what wires up swift-testing for `swift test`.
let languageMode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// Without a full Xcode, swift-testing lives in the Command Line Tools developer
// directory and SwiftPM does not add it to the search path on its own.
let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let commandLineToolsLibraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let needsToolsFrameworkPath =
    !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    && FileManager.default.fileExists(atPath: "\(commandLineToolsFrameworks)/Testing.framework")

let testSwiftSettings: [SwiftSetting] = needsToolsFrameworkPath
    ? languageMode + [.unsafeFlags(["-F", commandLineToolsFrameworks])]
    : languageMode
let testLinkerSettings: [LinkerSetting] = needsToolsFrameworkPath
    ? [.unsafeFlags(["-F", commandLineToolsFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", commandLineToolsLibraries])]
    : []

let package = Package(
    name: "SeatingChart",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SeatingChart",
            path: "Sources/SeatingChart",
            resources: [.process("Resources")],
            swiftSettings: languageMode
        ),
        .testTarget(
            name: "SeatingChartTests",
            dependencies: ["SeatingChart"],
            path: "Tests/SeatingChartTests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
