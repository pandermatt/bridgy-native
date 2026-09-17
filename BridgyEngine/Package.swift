// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BridgyEngine",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "BridgyEngine", targets: ["BridgyEngine"])
    ],
    targets: [
        .target(
            name: "BridgyEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BridgyEngineTests",
            dependencies: ["BridgyEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
