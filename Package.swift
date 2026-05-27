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
        .executableTarget(
            name: "Cribble",
            dependencies: [
                .product(name: "Textual", package: "textual"),
                .product(name: "Markdown", package: "swift-markdown")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CribbleTests",
            dependencies: ["Cribble"]
        )
    ]
)
