// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LighthouseKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LighthouseKit", targets: ["LighthouseKit"]),
        .library(name: "LighthouseUI", targets: ["LighthouseUI"]),
    ],
    targets: [
        .target(name: "LighthouseKit"),
        .target(
            name: "LighthouseUI", dependencies: ["LighthouseKit"],
            resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "LighthouseKitTests", dependencies: ["LighthouseKit"]),
    ]
)
