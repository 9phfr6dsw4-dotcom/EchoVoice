// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoVoice",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoVoiceCore", targets: ["EchoVoiceCore"]),
        .executable(name: "EchoVoiceApp", targets: ["EchoVoiceApp"])
    ],
    dependencies: [
        // Runs both engines. Scripts/prepare-models.sh applies checked fixes to this exact revision.
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "244458d7b61e54ff135073ddc9ed76782bb20758"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "0.12.0"),
        // Held at the versions mlx-audio-swift was tested with at that commit.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.4"),
        // Automatic updates. Pinned exactly; the packaged app embeds this framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "EchoVoiceCore"),
        .executableTarget(
            name: "EchoVoiceApp",
            dependencies: [
                "EchoVoiceCore",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                // The packaged app keeps Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "EchoVoiceModelTests",
            dependencies: [
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift")
            ],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "EchoVoiceTests",
            dependencies: ["EchoVoiceCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
