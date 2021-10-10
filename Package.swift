// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "video-kit",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "VideoKit",
            targets: ["VideoKit"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/Cartisim/cartisim-nio-client.git", from: "1.1.9"),
        .package(url: "https://github.com/Cartisim/swift-nio-transport-services.git", .branch("feature/update-udp-support-nio-2.33.0")),
        .package(url:  "https://github.com/SwiftNIOExtras/swift-nio-irc.git",
                 from: "0.8.0")
       
    ],
    targets: [
        .target(
            name: "VideoKit",
            dependencies: [
//                .product(name: "CartisimNIOClient", package: "cartisim-nio-client")
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOIRC", package: "swift-nio-irc")
            ]),
        .testTarget(
            name: "VideoKitTests",
            dependencies: ["VideoKit"]),
    ]
)
