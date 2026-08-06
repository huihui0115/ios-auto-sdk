// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AutoSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "AutoSDK", type: .static, targets: ["AutoSDK"])
    ],
    targets: [
        .target(
            name: "AutoSDK",
            path: "Sources/AutoSDK",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("UIKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Network"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Photos"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ImageIO"),
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "AutoSDKTests",
            dependencies: ["AutoSDK"],
            path: "Tests/AutoSDKTests"
        )
    ]
)
