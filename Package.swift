// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BezelCast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BezelCast"),
    ]
)
