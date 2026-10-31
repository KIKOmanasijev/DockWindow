// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DogBar", platforms: [.macOS(.v14)], products: [.executable(name: "DockWindow", targets: ["DockWindow"]), .library(name: "DockWindowCore", targets: ["DockWindowCore"])], targets: [.executableTarget(name: "DockWindow", dependencies: ["DockWindowCore"]), .target(name: "DockWindowCore"), .testTarget(name: "DockWindowCoreTests", dependencies: ["DockWindowCore"])], swiftLanguageModes: [.v5])
