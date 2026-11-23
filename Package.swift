// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "heft",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HeftCore", targets: ["HeftCore"]),
        .executable(name: "heft", targets: ["heft"])
    ],
    targets: [
        .target(
            name: "HeftCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "heft",
            dependencies: ["HeftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "HeftTests",
            dependencies: ["HeftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
