// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lyra",
    platforms: [
        .macOS("15.0")
    ],
    targets: [
        .executableTarget(
            name: "Lyra",
            path: "Sources/Lyra",
            resources: [
                .process("Assets.xcassets"),
                .copy("AppIcon.png")
            ],
            linkerSettings: [
                .linkedFramework("MediaPlayer"),
                .linkedFramework("MediaToolbox"),
                .linkedFramework("Accelerate")
            ]
        ),
        .testTarget(
            name: "LyraTests",
            dependencies: ["Lyra"],
            path: "Tests/LyraTests"
        )
    ]
)
