// swift-tools-version:5.10
import PackageDescription

// Niche's decisions that need no window and no Chromium: models, Arc import mapping, layout
// arithmetic. A package of its own so `swift test --package-path Packages/NicheCore` builds
// and runs without vendor/cef (a target in the root package would build CEF first).
let package = Package(
    name: "NicheCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NicheCore", targets: ["NicheCore"]),
    ],
    targets: [
        .target(name: "NicheCore"),
        .testTarget(name: "NicheCoreTests", dependencies: ["NicheCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageVersions: [.v5]
)
