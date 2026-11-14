// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-efatura",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // Request building, WS-Security header, response parsing. No networking.
        .library(name: "EFatura", targets: ["EFatura"]),
        // Mutual-TLS transport on AsyncHTTPClient, for servers (Vapor, Hummingbird) on macOS and Linux.
        .library(name: "EFaturaAsyncHTTPClient", targets: ["EFaturaAsyncHTTPClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
    ],
    targets: [
        .target(
            name: "EFatura",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "EFaturaAsyncHTTPClient",
            dependencies: [
                .target(name: "EFatura"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "EFaturaTests",
            dependencies: [
                .target(name: "EFatura"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
