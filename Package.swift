// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenGram",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", exact: "4.2.2"),
    ],
    targets: [
        .binaryTarget(
            name: "harper_bridgeFFI",
            path: "HarperBridge.xcframework"
        ),
        .target(
            name: "OpenGramLib",
            dependencies: ["harper_bridgeFFI", "KeychainAccess"],
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
            dependencies: ["OpenGramLib", "KeychainAccess"],
            path: "OpenGramTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
