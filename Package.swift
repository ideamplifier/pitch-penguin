// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PitchPenguinDependencies",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit", from: "5.6.0")
    ],
    targets: [
        .target(
            name: "PitchPenguinDependencies",
            dependencies: [
                "AudioKit",
                "SoundpipeAudioKit"
            ])
    ]
)