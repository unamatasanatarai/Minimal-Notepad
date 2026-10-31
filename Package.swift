// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MinimalNotepad",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "MinimalNotepad",
            targets: ["MinimalNotepad"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MinimalNotepad",
            dependencies: [],
            path: "Sources"
        )
    ]
)
