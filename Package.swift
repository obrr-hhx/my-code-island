// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodeIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeIsland", targets: ["CodeIsland"]),
        .executable(name: "code-island-bridge", targets: ["Bridge"])
    ],
    targets: [
        .target(
            name: "CodeIslandShared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "CodeIsland",
            dependencies: ["CodeIslandShared"],
            path: "Sources/CodeIsland",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        ),
        .executableTarget(
            name: "Bridge",
            dependencies: ["CodeIslandShared"],
            path: "Sources/Bridge"
        )
    ]
)
