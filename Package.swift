// swift-tools-version:5.10
import PackageDescription

// CEF (Chromium Embedded Framework) lives in vendor/cef, fetched by
// scripts/fetch-cef.sh, with its C++ wrapper built by CMake into
// vendor/cef/build/libcef_dll_wrapper.
let cefRoot = "\(Context.packageDirectory)/vendor/cef"

// Same flags CEF uses for its own wrapper (vendor/cef/cmake/cef_variables.cmake),
// so the ABI of the wrapper classes matches.
let cefCXXFlags: [String] = [
    "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics",
    "-fobjc-call-cxx-cdtors", "-fno-strict-aliasing",
    "-Wno-unused-parameter", "-Wno-deprecated-declarations",
    "-I", cefRoot,
]

let cefLinkerFlags: [String] = [
    "-L\(cefRoot)/build/libcef_dll_wrapper",
]

// Sparkle, the updater framework Arc ships, lives in vendor/sparkle (scripts/fetch-sparkle.sh);
// scripts/build.sh copies Sparkle.framework into Niche.app/Contents/Frameworks.
let sparkleRoot = "\(Context.packageDirectory)/vendor/sparkle"

let package = Package(
    name: "Niche",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Niche", targets: ["Niche"]),
        .executable(name: "NicheHelper", targets: ["NicheHelper"]),
        // Loaded by the Dock, not by Niche; scripts/build.sh wraps it in
        // Niche.app/Contents/PlugIns/NicheDockTile.docktileplugin.
        .library(name: "NicheDockTile", type: .dynamic, targets: ["NicheDockTile"]),
    ],
    // Models and decisions that need no AppKit or CEF, with tests that run without vendor/cef.
    dependencies: [.package(path: "Packages/NicheCore")],
    targets: [
        // Objective-C++ bridge between Swift and CEF.
        .target(
            name: "NicheCEF",
            path: "Sources/NicheCEF",
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(cefCXXFlags + ["-fobjc-arc"])],
            linkerSettings: [
                .unsafeFlags(cefLinkerFlags),
                .linkedLibrary("cef_dll_wrapper"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
            ]
        ),
        // Subprocess executable (renderer, GPU, utility...). Bundled five
        // times as "Niche Helper*.app" inside Niche.app/Contents/Frameworks.
        .executableTarget(
            name: "NicheHelper",
            path: "Sources/NicheHelper",
            cxxSettings: [.unsafeFlags(cefCXXFlags)],
            linkerSettings: [
                .unsafeFlags(cefLinkerFlags),
                .linkedLibrary("cef_dll_wrapper"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
            ]
        ),
        // Dock tile plug-in: keeps the icon picked in Settings after Niche quits.
        .target(
            name: "NicheDockTile",
            path: "Sources/NicheDockTile",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // The browser itself: AppKit window, SwiftUI sidebar and command bar.
        .executableTarget(
            name: "Niche",
            dependencies: ["NicheCEF", .product(name: "NicheCore", package: "NicheCore")],
            path: "Sources/Niche",
            swiftSettings: [.unsafeFlags(["-F", sparkleRoot]), .unsafeFlags(["-Onone"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-F", sparkleRoot, "-framework", "Sparkle",
                                           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx20
)
