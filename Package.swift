// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LastCall",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "LastCallKit", targets: ["LastCallKit"]),
        .executable(name: "LastCallApp", targets: ["LastCallApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/dmccullum/DMKit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "LastCallKit",
            path: "Sources/LastCallKit"
        ),
        .executableTarget(
            name: "LastCallApp",
            dependencies: [
                "LastCallKit",
                .product(name: "DMKit", package: "DMKit")
            ],
            path: "Sources/LastCallApp",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "LastCallKitTests",
            dependencies: ["LastCallKit"],
            path: "Tests/LastCallKitTests"
        )
    ]
)
