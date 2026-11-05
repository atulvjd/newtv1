// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Vox", targets: ["Vox"])],
    targets: [
        .target(name: "VoxCore"),
        .executableTarget(name: "Vox", dependencies: ["VoxCore"]),
        .testTarget(name: "VoxCoreTests", dependencies: ["VoxCore"])
    ]
)
