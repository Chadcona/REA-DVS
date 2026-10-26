// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenDeck", targets: ["OpenDeck"])
    ],
    targets: [
        .executableTarget(name: "OpenDeck")
    ]
)
