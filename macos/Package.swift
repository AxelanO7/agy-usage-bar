// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgyUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AgyUsageBar", path: "Sources/AgyUsageBar")
    ]
)
