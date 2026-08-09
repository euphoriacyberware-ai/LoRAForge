// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaggingCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "TaggingCore", targets: ["TaggingCore"]),
    ],
    targets: [
        .target(name: "TaggingCore"),
        .testTarget(name: "TaggingCoreTests", dependencies: ["TaggingCore"]),
    ]
)
