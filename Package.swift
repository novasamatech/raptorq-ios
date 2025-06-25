// swift-tools-version: 6.0
import PackageDescription

let name = "RaptorQ-iOS"

let package = Package(
    name: name,
    products: [
        .library(
            name: name,
            targets: [name]
        ),
    ],
    targets: [
        .binaryTarget(
            name: name,
            path: "./bindings/xcframework/raptorq.xcframework"
        )
    ]
)
