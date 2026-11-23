// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cordova-datadog-rum",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "cordova-datadog-rum",
            targets: ["CordovaDatadogRum"]
        )
    ],
    dependencies: [
        // cordova-ios rewrites this dependency to a local relative path during build
        .package(url: "https://github.com/apache/cordova-ios.git", branch: "master"),
        .package(url: "https://github.com/DataDog/dd-sdk-ios.git", from: "3.22.0")
    ],
    targets: [
        .target(
            name: "CordovaDatadogRum",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .product(name: "DatadogCore", package: "dd-sdk-ios"),
                .product(name: "DatadogRUM", package: "dd-sdk-ios"),
                .product(name: "DatadogWebViewTracking", package: "dd-sdk-ios")
            ],
            path: "src/ios",
            sources: ["DatadogRum.swift"]
        )
    ]
)
