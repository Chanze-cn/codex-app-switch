// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CodexProfileManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexProfileManager", targets: ["CodexProfileManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
    ],
    targets: [
        .executableTarget(
            name: "CodexProfileManager",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
