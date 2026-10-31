// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DogBar", platforms: [.macOS("26.0")], products: [.executable(name: "DogBar", targets: ["DogBar"]), .library(name: "DogBarCore", targets: ["DogBarCore"])], targets: [.executableTarget(name: "DogBar", dependencies: ["DogBarCore"]), .target(name: "DogBarCore"), .testTarget(name: "DogBarCoreTests", dependencies: ["DogBarCore"])], swiftLanguageModes: [.v5])
