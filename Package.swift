// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Pipeable",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "Pipeable",
            targets: ["Pipeable"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Pipeable",
            dependencies: [],
            exclude: ["Samples"] // Exclude the Samples directory
        ),

        .testTarget(
            name: "PipeableTests",
            dependencies: ["Pipeable"])
    ]
)
