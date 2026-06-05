// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CodexProfileManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexProfileManager", targets: ["CodexProfileManager"])
    ],
    targets: [
        .executableTarget(
            name: "CodexProfileManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
