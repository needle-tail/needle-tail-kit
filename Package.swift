// swift-tools-version:5.8
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
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", revision: "01fc0ae7e5de9199d53932582a28c0e59b883f5f"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.56.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", .upToNextMajor(from: "1.12.1")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from: "2.24.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.1.3")),
//        .package(url: "https://github.com/needle-tail/CypherTextKit.git", revision: "63326570b308415c396d2eae9c58e8b2cca18298"),
        .package(path: "../ForkedCypherTextKit/CypherTextKit"),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "2.1.0")),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "0.0.3")),
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/needle-tail/swift-data-to-file.git", branch: "main"),
        .package(url: "https://github.com/needle-tail/needletail-media-kit.git", branch: "main")
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
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            .product(name: "CypherMessaging", package: "CypherTextKit"),
            .product(name: "MessagingHelpers", package: "CypherTextKit"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            .product(name: "Atomics", package: "swift-atomics"),
            .product(name: "Algorithms", package: "swift-algorithms"),
            .target(name: "NeedleTailHelpers"),
            .target(name: "NeedleTailProtocol"),
            .product(name: "SwiftDTF", package: "swift-data-to-file"),
            .product(name: "NeedletailMediaKit", package: "needletail-media-kit")
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
