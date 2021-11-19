// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "connection-kit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ConnectionKit",
            targets: ["ConnectionKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Cartisim/swift-nio-transport-services.git", .branch("feature/update-udp-support-nio-2.33.0")),
        .package(url:  "https://github.com/SwiftNIOExtras/swift-nio-irc.git", from: "0.8.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.7.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "0.0.5")),
        .package(url: "https://github.com/orlandos-nl/CypherTextKit.git", .branch("master")),
        .package(url: "https://github.com/Cartisim/swift-nio-irc-client.git", .branch("develop"))
       
    ],
    targets: [
        .target(
            name: "ConnectionKit",
        dependencies: [
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "NIOIRC", package: "swift-nio-irc"),
            .product(name: "IRC", package: "swift-nio-irc-client"),
            .product(name: "NIOExtras", package: "swift-nio-extras"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "CypherMessaging", package: "CypherTextKit"),
            .product(name: "MessagingHelpers", package: "CypherTextKit")
        ]),
        .testTarget(
            name: "ConnectionKitTests",
            dependencies: ["ConnectionKit"]),
    ]
)
