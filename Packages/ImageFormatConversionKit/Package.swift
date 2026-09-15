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
    dependencies: [
        .package(
            url: "https://github.com/BB9z/LAME-xcframework.git",
            exact: "3.100.3"
        )
    ],
    targets: [
        .target(
            name: "ImageFormatConversionKit",
            dependencies: [
                .product(name: "LAME", package: "LAME-xcframework")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ImageFormatConversionKitTests",
            dependencies: ["ImageFormatConversionKit"]
        )
    ]
)
