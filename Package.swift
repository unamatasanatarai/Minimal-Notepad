// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Notepad",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "Notepad",
            targets: ["Notepad"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Notepad",
            dependencies: [],
            path: "Sources"
        )
    ]
)
