// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Stillbreak",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StillbreakCore", targets: ["StillbreakCore"]),
        .executable(name: "Stillbreak", targets: ["Stillbreak"]),
        .executable(name: "StillbreakRepair", targets: ["StillbreakRepair"]),
        .executable(name: "StillbreakSmoke", targets: ["StillbreakSmoke"]),
    ],
    targets: [
        .target(name: "StillbreakCore"),
        .executableTarget(
            name: "Stillbreak",
            dependencies: ["StillbreakCore"]
        ),
        .executableTarget(
            name: "StillbreakRepair",
            dependencies: ["StillbreakCore"]
        ),
        .executableTarget(
            name: "StillbreakSmoke",
            dependencies: ["StillbreakCore"]
        ),
        .testTarget(
            name: "StillbreakCoreTests",
            dependencies: ["StillbreakCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
                .linkedFramework("Testing"),
            ]
        ),
    ]
)
