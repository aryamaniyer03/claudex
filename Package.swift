// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudex",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.11.2")
    ],
    targets: [
        .executableTarget(
            name: "Claudex",
            dependencies: ["SwiftTerm"],
            path: "Sources/TerminalHub",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
