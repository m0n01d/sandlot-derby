// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DerbyCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "DerbyCore", targets: ["DerbyCore"]),
    ],
    targets: [
        .target(name: "DerbyCore"),
        .testTarget(name: "DerbyCoreTests", dependencies: ["DerbyCore"]),
    ]
)
