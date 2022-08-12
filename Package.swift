// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needle-tail-kit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
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
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.13.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.41.1"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.12.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.21.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.1.3")),
        .package(url: "https://github.com/needle-tail/CypherTextKit.git", revision: "2b0569683624b69865779f7f5fe70a2fcf3bbaf8"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.1.0")
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
