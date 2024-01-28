// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "PipeableSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "PipeableSDK",
            type: .dynamic,  // This specifies the library as dynamic
            targets: ["PipeableSDK"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PipeableSDK",
            dependencies: [],
            path: "Sources/PipeableSDK",
            exclude: ["sophiajs"],
            resources: [
                .process("Resources")
            ]
        ),

        .testTarget(
            name: "PipeableSDKTests",
            dependencies: ["PipeableSDK"],
            path: "PipeableTests"
        )
    ]
)
