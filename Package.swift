// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacPulse", platforms: [.macOS(.v14)],
    products: [.library(name: "MacPulseCore", targets: ["MacPulseCore"]), .executable(name: "MacPulse", targets: ["MacPulse"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "MacPulseCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MacPulse", dependencies: ["MacPulseCore"]),
        .testTarget(name: "MacPulseCoreTests", dependencies: ["MacPulseCore"])
    ]
)
