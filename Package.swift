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
        .package(url:"https://github.com/tannerdsilva/TToolkit.git", .revision("c2f5fa3195c7ac080c31c2ede05ba46e12eaf98ac349fa6e99a33bce41e5d4b15ce26d31ab6a458f")),
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
