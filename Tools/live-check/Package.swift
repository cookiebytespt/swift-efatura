// swift-tools-version:6.0
import PackageDescription

// A command-line check of swift-efatura against AT's real webservice.
// Kept in its own package so the library itself ships no executable.
let package = Package(
    name: "efatura-live-check",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "efatura-live-check",
            dependencies: [
                .product(name: "EFatura", package: "swift-efatura"),
                .product(name: "EFaturaAsyncHTTPClient", package: "swift-efatura"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
            ]
        ),
    ]
)
