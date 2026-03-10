// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiquidGlassChat",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "LiquidGlassChat",
            targets: ["LiquidGlassChat"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0"),
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "LiquidGlassChat",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "Highlightr",
                "LaTeXSwiftUI",
            ],
            path: "LiquidGlassChat"
        ),
    ]
)
