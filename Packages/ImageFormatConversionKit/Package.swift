// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImageFormatConversionKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ImageFormatConversionKit",
            targets: ["ImageFormatConversionKit"]
        )
    ],
    targets: [
        .target(
            name: "ImageFormatConversionKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ImageFormatConversionKitTests",
            dependencies: ["ImageFormatConversionKit"]
        )
    ]
)
