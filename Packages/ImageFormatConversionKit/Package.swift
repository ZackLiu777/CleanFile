// swift-tools-version: 6.0
// 转换组件的 Swift Package 定义。
//
// 此清单声明组件支持的平台、库产品、资源和测试目标，以及音频编码所需的
// LAME 二进制依赖。首行的工具链版本声明由 Swift Package Manager 读取，
// 因此文件说明放在该声明之后；依赖版本与目标设置均由项目统一维护。

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
