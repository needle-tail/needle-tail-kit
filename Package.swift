// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needle-tail-kit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "NeedleTailKit",
            targets: ["NeedleTailKit"]),
        .library(
            name: "NeedleTailProtocol",
            targets: ["NeedleTailProtocol"]),
        .library(
            name: "NeedleTailHelpers",
            targets: ["NeedleTailHelpers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/needle-tail/swift-nio-transport-services.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.41.1"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.12.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.21.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.1.3")),
        .package(url: "https://github.com/needle-tail/CypherTextKit.git", branch: "feature/async-await"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.1.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "0.0.3"),
        .package(path: "../spine-tailed-kit")
    ],
    targets: [
        .target(
            name: "NeedleTailKit",
        dependencies: [
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "NIOExtras", package: "swift-nio-extras"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "CypherMessaging", package: "CypherTextKit"),
            .product(name: "MessagingHelpers", package: "CypherTextKit"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            .product(name: "SpineTailedKit", package: "spine-tailed-kit"),
            .target(name: "NeedleTailHelpers"),
            .target(name: "NeedleTailProtocol")
        ]),
        .target(
            name: "NeedleTailProtocol",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "CypherMessaging", package: "CypherTextKit"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .target(name: "NeedleTailHelpers")
            ]),
        .target(
            name: "NeedleTailHelpers",
            dependencies: [
                .product(name: "CypherMessaging", package: "CypherTextKit")
            ]),
        .testTarget(
            name: "NeedleTailKitTests",
            dependencies: ["NeedleTailKit"]),
    ]
)
