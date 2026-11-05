// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Newtv1",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Newtv1", targets: ["Newtv1"])],
    targets: [
        .target(name: "Newtv1Core"),
        .executableTarget(name: "Newtv1", dependencies: ["Newtv1Core"]),
        .executableTarget(name: "Newtv1Setup", dependencies: ["Newtv1Core"]),
        .executableTarget(name: "Newtv1CoreChecks", dependencies: ["Newtv1Core"], path: "Tests/Newtv1CoreTests")
    ]
)
