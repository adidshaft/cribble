// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cribble",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "Cribble", targets: ["Cribble"])
    ],
    dependencies: [
        .package(path: "Vendor/textual"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
        // On-device LLM engine for the Local Chat HUD (Apple MLX). Heavy native
        // dependency; isolated to `MLXChatEngine.swift` via `canImport(MLXLLM)`.
        // MLX's HuggingFace integration is "bring your own client": the
        // `#hubDownloader()` / `#huggingFaceTokenizerLoader()` macros bridge to
        // the `HuggingFace` and `Tokenizers` modules below.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        // Objective-C target whose load-time constructor installs the
        // NSBundle path redirect before any Swift `Bundle.module` initializer
        // runs. Kept separate because SPM can't mix .m and .swift in one
        // target.
        .target(
            name: "CribbleBundleRedirect",
            // The NSBundle `initWithPath:` swizzle hand-calls the original IMP,
            // which belongs to the ObjC `init` family (+1 return). Under ARC the
            // C-style call is treated as +0, so the caller over-releases — a
            // latent bug that MLX's Metal-library probing triggers into a crash.
            // Compiling this one file without ARC restores correct MRC ownership.
            cSettings: [.unsafeFlags(["-fno-objc-arc"])]
        ),
        .executableTarget(
            name: "Cribble",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Textual", package: "textual"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                "CribbleBundleRedirect"
            ],
            resources: [
                .process("Resources/AppIconLight.png"),
                .process("Resources/AppIconDark.png"),
                .copy("Resources/Mermaid"),
                .copy("Resources/DemoNotes")
            ]
        ),
        .testTarget(
            name: "CribbleTests",
            dependencies: ["Cribble"]
        )
    ]
)
