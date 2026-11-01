// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DogBar", platforms: [.macOS("26.0")], products: [.executable(name: "DogBar", targets: ["DogBar"]), .library(name: "DogBarCore", targets: ["DogBarCore"])],
    // Exact pin: updating the updater is a reviewed change. No target links Sparkle. Bundle
    // packaging embeds the checksum-verified framework, and the app loads it only after
    // checking that it is signed with the app's own certificate (see Docs/Updates.md).
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [.executableTarget(name: "DogBar", dependencies: ["DogBarCore", "DogBarSparkleBridge"]), .target(name: "DogBarSparkleBridge"),
        .target(name: "DogBarCore"), .testTarget(name: "DogBarCoreTests", dependencies: ["DogBarCore"])], swiftLanguageModes: [.v5])
