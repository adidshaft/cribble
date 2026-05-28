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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        // Objective-C target whose load-time constructor installs the
        // NSBundle path redirect before any Swift `Bundle.module` initializer
        // runs. Kept separate because SPM can't mix .m and .swift in one
        // target.
        .target(
            name: "CribbleBundleRedirect"
        ),
        .executableTarget(
            name: "Cribble",
            dependencies: [
                .product(name: "Textual", package: "textual"),
                .product(name: "Markdown", package: "swift-markdown"),
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
