// swift-tools-version:5.9
//
// Runs the project's EXISTING XCTest files (TimelineMapperTests, ShortFoundationTests) on macOS with `swift test`,
// against the very same source files the iOS app and the headless renderer compile (symlinks, no copies).
// Layering is by file list: tools/core-files.txt (Core) + tools/rendering-files.txt (Rendering). This package only
// exists to execute tests on a Mac; it adds no behaviour. Refresh links with tools/swiftpm-short/sync-links.sh.
import PackageDescription

let package = Package(
    name: "TakeLayerShortKit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TakeLayerShortKit"),
        .testTarget(name: "TakeLayerShortKitTests", dependencies: ["TakeLayerShortKit"]),
    ]
)
