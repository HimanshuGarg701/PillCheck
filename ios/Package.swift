// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PillCheckCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "PillCheckCore", targets: ["PillCheckCore"])],
    targets: [
        .target(name: "PillCheckCore", path: "PillCheck/Core"),
        .testTarget(name: "PillCheckCoreTests", dependencies: ["PillCheckCore"], path: "PillCheckCore/Tests/PillCheckCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
