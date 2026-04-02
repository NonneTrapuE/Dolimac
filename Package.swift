// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoliMac",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DoliMac",
            path: "Sources/DoliMac",
            resources: [
                .process("../../Resources/Info.plist")
            ]
        )
    ]
)
