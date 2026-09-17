// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Duotlet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.14.2"),
    ],
    targets: [
        .target(
            name: "LidAngleKit",
            path: "Sources/LidAngleKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Duotlet",
            dependencies: [
                "LidAngleKit",
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            path: "Sources/Duotlet",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lidprobe",
            dependencies: ["LidAngleKit"],
            path: "Sources/lidprobe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DuotletTests",
            dependencies: ["Duotlet"],
            path: "Tests/DuotletTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
