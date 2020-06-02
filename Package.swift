// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "guarddog",
	platforms: [
    	.macOS(.v10_14)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url:"https://github.com/tannerdsilva/TToolkit.git", .revision("132f5abd2c3e7d4aa5713cc182e1ba2492606a2e")),
        .package(url:"https://github.com/tannerdsilva/Commander.git", .upToNextMinor(from:"0.9.1")),
        .package(url:"https://github.com/tannerdsilva/PythonKit.git", .branch("master")),
        .package(url:"https://github.com/IBM-Swift/BlueSignals.git", .upToNextMinor(from:"1.0.21"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "guarddog",
            dependencies: ["TToolkit", "Commander", "PythonKit", "Signals"]),
        .testTarget(
            name: "guarddogTests",
            dependencies: ["guarddog"]),
    ]
)
