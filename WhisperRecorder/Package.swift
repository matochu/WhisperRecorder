// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WhisperRecorder",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "WhisperRecorder",
            targets: ["WhisperRecorder"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.0.0")
    ],
    targets: [
        // C wrapper for whisper.cpp
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            cSettings: [
                .headerSearchPath("../../include"),
                .headerSearchPath("../../ggml/include"),
                .unsafeFlags(["-I", "../include"]),
                .unsafeFlags(["-I", "../ggml/include"]),
            ]
        ),
        // Main Swift executable
        .executableTarget(
            name: "WhisperRecorder",
            dependencies: [
                "KeyboardShortcuts",
                "CWhisper",
            ],
            path: "Sources/WhisperRecorder",
            resources: [
                // Make sure KeyboardShortcuts resources are included
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedLibrary("whisper", .when(platforms: [.macOS])),
                .unsafeFlags(["-Llibs"]),
            ]
        ),
        // Test targets
        .testTarget(
            name: "WhisperRecorderTests",
            dependencies: ["WhisperRecorder"],
            path: "Tests/WhisperRecorderTests",
            resources: [
                .copy("TestAudioFiles/")
            ]
        ),
        .testTarget(
            name: "WhisperRecorderE2ETests",
            dependencies: ["WhisperRecorder", "WhisperRecorderTests"],
            path: "Tests/WhisperRecorderE2ETests",
            resources: [
                .copy("TestAudioFiles/")
            ]
        ),
    ]
)
