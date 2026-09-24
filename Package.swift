// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ActiveBreak",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ActiveBreakCore", targets: ["ActiveBreakCore"]),
        .executable(name: "ActiveBreak", targets: ["ActiveBreak"]),
        .executable(name: "ActiveBreakRepair", targets: ["ActiveBreakRepair"]),
        .executable(name: "ActiveBreakSmoke", targets: ["ActiveBreakSmoke"]),
    ],
    targets: [
        .target(name: "ActiveBreakCore"),
        .executableTarget(
            name: "ActiveBreak",
            dependencies: ["ActiveBreakCore"]
        ),
        .executableTarget(
            name: "ActiveBreakRepair",
            dependencies: ["ActiveBreakCore"]
        ),
        .executableTarget(
            name: "ActiveBreakSmoke",
            dependencies: ["ActiveBreakCore"]
        ),
        .testTarget(
            name: "ActiveBreakCoreTests",
            dependencies: ["ActiveBreakCore"],
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
