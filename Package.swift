// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TimeTrail",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TimeTrail", path: "Sources/TimeTrail")
    ]
)
