// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needle-tail-kit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "NeedleTailKit",
            targets: ["NeedleTailKit", "AsyncIRC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.11.3"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.7.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "0.0.5")),
//        .package(url: "https://github.com/orlandos-nl/CypherTextKit.git", .branch("feature/async-await")),
        .package(url: "https://github.com/needle-tail/CypherTextKit.git", .branch("feature/async-await")),
        .package(url: "https://github.com/adam-fowler/async-collections.git", from: "0.0.1"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.1.0")
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
            .product(name: "AsyncCollections", package: "async-collections"),
            .target(name: "AsyncIRC"),
        ]),
        .target(
            name: "AsyncIRC",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "AsyncCollections", package: "async-collections"),
                .product(name: "CypherMessaging", package: "CypherTextKit"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-disable-availability-checking",
                ])
            ]
        ),
        .testTarget(
            name: "NeedleTailKitTests",
            dependencies: ["NeedleTailKit"]),
    ]
)
