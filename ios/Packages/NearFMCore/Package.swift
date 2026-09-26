// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NearFMCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "NearFMCore", targets: ["NearFMCore"])],
    targets: [
        .target(name: "NearFMCore"),
        .testTarget(name: "NearFMCoreTests", dependencies: ["NearFMCore"])
    ]
)
