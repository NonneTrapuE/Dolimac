// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DolibarrBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DolibarrBar",
            path: "Sources/DolibarrBar",
            resources: [
                .process("../../Resources/Info.plist")
            ]
        )
    ]
)
