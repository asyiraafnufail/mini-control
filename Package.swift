// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MiniControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MiniControl", targets: ["MiniControl"])
    ],
    targets: [
        .executableTarget(
            name: "MiniControl",
            path: "Sources/MiniControl",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
