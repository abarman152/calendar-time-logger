// swift-tools-version: 6.2
import PackageDescription

// CalendarTimeLoggerKit holds the platform-neutral core of Calendar Time Logger:
// domain models, the session state machine, persistence, and service logic.
// It deliberately contains no AppKit or SwiftUI code so it can be reused by
// future platforms (see Documentation/Decisions/ADR-011-core-swift-package.md).
let package = Package(
    name: "CalendarTimeLoggerKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CalendarTimeLoggerKit", targets: ["CalendarTimeLoggerKit"])
    ],
    targets: [
        .target(
            name: "CalendarTimeLoggerKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CalendarTimeLoggerKitTests",
            dependencies: ["CalendarTimeLoggerKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
