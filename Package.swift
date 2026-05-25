// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cribble",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Cribble", targets: ["Cribble"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Cribble",
            dependencies: [
                .product(name: "Textual", package: "textual"),
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(
            name: "CribbleTests",
            dependencies: ["Cribble"]
        )
    ]
)
