// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenGram",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "OpenGramLib",
            path: "OpenGram",
            exclude: ["App/main.swift"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "OpenGram",
            dependencies: ["OpenGramLib"],
            path: "OpenGramEntry",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpenGramTests",
            dependencies: ["OpenGramLib"],
            path: "OpenGramTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
