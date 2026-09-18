// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BridgyEngine",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "BridgyEngine", targets: ["BridgyEngine"]),
        .library(name: "BridgyTraining", targets: ["BridgyTraining"])
    ],
    targets: [
        .target(
            name: "BridgyEngine",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Optimised even in Debug. The engines are tight loops over
                // arrays, and unoptimised they run about a hundred times slower —
                // a random 35×35 game went from half a millisecond to over fifty,
                // and every search and tournament paid the same. Running the app
                // from Xcode is a Debug build, so without this "the game is slow"
                // was mostly the build configuration. The app itself stays
                // debuggable; only this package is optimised.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                // The current CBLAS headers; the older interface is deprecated.
                .unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])
            ]
        ),
        // Training needs Metal; playing does not. Kept apart so the engine
        // stays a pure CPU library.
        .target(
            name: "BridgyTraining",
            dependencies: ["BridgyEngine"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-O"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "BridgyEngineTests",
            dependencies: ["BridgyEngine", "BridgyTraining"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
