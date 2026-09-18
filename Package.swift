// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RoonVolume", platforms: [.macOS(.v13)], products: [.executable(name: "RoonVolume", targets: ["RoonVolume"])], targets: [
    .target(name: "VolumeCore"),
    .executableTarget(name: "RoonVolume", dependencies: ["VolumeCore"]),
    .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"])
], swiftLanguageModes: [.v5])
