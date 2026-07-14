// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrowserProxy",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BrowserProxy",
            path: "Sources/BrowserProxy",
            swiftSettings: [
                // AppKit app: run everything on the main actor by default.
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
