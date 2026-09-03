import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageFormatConversionKit

@Suite("Image conversion engine")
struct ImageConversionEngineTests {
    // Required: fixed transparent fixture, decoded pixel contract (not UI snapshots).
    @Test("Selected background is encoded into transparent pixels and square padding",
          arguments: ImageBackground.allCases, [ImageResizePolicy.original, .square1024])
    func backgroundPixels(background: ImageBackground, resize: ImageResizePolicy) async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }
        let source = workspace.root.appendingPathComponent("transparent.png")
        try TestImageFactory.writeStillImage(to: source, type: .png, width: 40, height: 20, alpha: 0)
        let result = try await ImageConversionEngine().convert(ImageConversionRequest(
            sourceURL: source, destinationDirectory: workspace.output, outputFormat: .png,
            resizePolicy: resize, background: background
        ))
        let imageSource = try #require(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for offset in [0, (image.height / 2 * image.width + image.width / 2) * 4] {
            if background == .transparent {
                #expect(pixels[offset + 3] == 0)
            } else {
                #expect(pixels[offset + 3] == 255)
                let expected: UInt8 = background == .white ? 255 : 0
                #expect(pixels[offset] == expected)
                #expect(pixels[offset + 1] == expected)
                #expect(pixels[offset + 2] == expected)
            }
        }
    }

    @Test("Transparent JPEG is rejected rather than silently flattened")
    func rejectsTransparentJPEG() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }
        await #expect(throws: ImageConversionError.unsupportedOutputFormat(.jpeg)) {
            try await ImageConversionEngine().convert(ImageConversionRequest(
                sourceURL: workspace.root.appendingPathComponent("unused.png"),
                destinationDirectory: workspace.output, outputFormat: .jpeg, background: .transparent
            ))
        }
    }

    // Required: fixed fixtures verify exact dimensions and preserved source bytes.
    @Test("Square preset produces exactly 1024 pixels for every aspect ratio", arguments: [
        [400, 200], [200, 400], [80, 80], [2048, 1024]
    ])
    func squareOutput(dimensions: [Int]) async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }
        let source = workspace.root.appendingPathComponent("square-input.png")
        try TestImageFactory.writeStillImage(to: source, type: .png, width: dimensions[0], height: dimensions[1])
        let original = try Data(contentsOf: source)
        let engine = ImageConversionEngine()
        let result = try await engine.convert(ImageConversionRequest(
            sourceURL: source, destinationDirectory: workspace.output,
            outputFormat: .png, resizePolicy: ImageResizePreset.square1024.policy
        ))
        let info = try await engine.inspect(result.outputURL)
        #expect(result.pixelWidth == 1024 && result.pixelHeight == 1024)
        #expect(info.pixelWidth == 1024 && info.pixelHeight == 1024)
        #expect(try Data(contentsOf: source) == original)
        let encoded = try JSONEncoder().encode(ImageResizePreset.square1024.policy)
        #expect(try JSONDecoder().decode(ImageResizePolicy.self, from: encoded) == .square1024)
    }

    @Test("PNG converts to JPEG and remains inspectable")
    func convertsPNGToJPEG() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        #expect(ImageConversionEngine.supportedOutputFormats.contains(.jpeg))
        let sourceURL = workspace.root.appendingPathComponent("alpha-source.png")
        try TestImageFactory.writeStillImage(
            to: sourceURL,
            type: .png,
            width: 64,
            height: 40,
            alpha: 0.45
        )

        let engine = ImageConversionEngine()
        let result = try await engine.convert(
            ImageConversionRequest(
                sourceURL: sourceURL,
                destinationDirectory: workspace.output,
                outputFormat: .jpeg,
                quality: 0.8,
                metadataPolicy: .removeAll
            )
        )

        #expect(result.outputURL.pathExtension == "jpg")
        #expect(result.pixelWidth == 64)
        #expect(result.pixelHeight == 40)
        #expect(result.outputBytes > 0)

        let outputInfo = try await engine.inspect(result.outputURL)
        #expect(outputInfo.pixelWidth == 64)
        #expect(outputInfo.pixelHeight == 40)
        #expect(outputInfo.frameCount == 1)
    }

    @Test("Fit resize preserves the aspect ratio")
    func resizesProportionally() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let sourceURL = workspace.root.appendingPathComponent("wide.png")
        try TestImageFactory.writeStillImage(
            to: sourceURL,
            type: .png,
            width: 400,
            height: 200
        )

        let engine = ImageConversionEngine()
        let result = try await engine.convert(
            ImageConversionRequest(
                sourceURL: sourceURL,
                destinationDirectory: workspace.output,
                outputFormat: .png,
                resizePolicy: .fit(maxPixelDimension: 100)
            )
        )

        #expect(result.pixelWidth == 100)
        #expect(result.pixelHeight == 50)
    }

    @Test("EXIF orientation is baked into the output pixels")
    func normalizesOrientation() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let sourceURL = workspace.root.appendingPathComponent("rotated.jpg")
        try TestImageFactory.writeStillImage(
            to: sourceURL,
            type: .jpeg,
            width: 80,
            height: 40,
            properties: [kCGImagePropertyOrientation: 6]
        )

        let engine = ImageConversionEngine()
        let result = try await engine.convert(
            ImageConversionRequest(
                sourceURL: sourceURL,
                destinationDirectory: workspace.output,
                outputFormat: .png,
                metadataPolicy: .removeAll
            )
        )

        #expect(result.pixelWidth == 40)
        #expect(result.pixelHeight == 80)
    }

    @Test("Concurrent conversions reserve different output names")
    func reservesUniqueNames() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let sourceURL = workspace.root.appendingPathComponent("same-name.png")
        try TestImageFactory.writeStillImage(
            to: sourceURL,
            type: .png,
            width: 32,
            height: 32
        )

        let request = ImageConversionRequest(
            sourceURL: sourceURL,
            destinationDirectory: workspace.output,
            outputFormat: .jpeg,
            collisionPolicy: .makeUnique
        )
        let engine = ImageConversionEngine()

        async let first = engine.convert(request)
        async let second = engine.convert(request)
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult.outputURL != secondResult.outputURL)
        #expect(FileManager.default.fileExists(atPath: firstResult.outputURL.path))
        #expect(FileManager.default.fileExists(atPath: secondResult.outputURL.path))
    }

    @Test("Remove GPS keeps the conversion but strips location metadata")
    func removesGPSMetadata() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let sourceURL = workspace.root.appendingPathComponent("located.jpg")
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLatitude: 25.033,
            kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSLongitude: 121.5654
        ]
        try TestImageFactory.writeStillImage(
            to: sourceURL,
            type: .jpeg,
            width: 48,
            height: 48,
            properties: [kCGImagePropertyGPSDictionary: gps]
        )

        let sourceProperties = try #require(TestImageFactory.properties(at: sourceURL))
        #expect(sourceProperties[kCGImagePropertyGPSDictionary] != nil)

        let engine = ImageConversionEngine()
        let result = try await engine.convert(
            ImageConversionRequest(
                sourceURL: sourceURL,
                destinationDirectory: workspace.output,
                outputFormat: .jpeg,
                metadataPolicy: .removeGPS
            )
        )

        let outputProperties = try #require(TestImageFactory.properties(at: result.outputURL))
        #expect(outputProperties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test("Animated input is rejected without partial output")
    func rejectsAnimatedInput() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let sourceURL = workspace.root.appendingPathComponent("animated.gif")
        try TestImageFactory.writeAnimatedGIF(to: sourceURL, width: 24, height: 24)

        let engine = ImageConversionEngine()
        let request = ImageConversionRequest(
            sourceURL: sourceURL,
            destinationDirectory: workspace.output,
            outputFormat: .png
        )

        do {
            _ = try await engine.convert(request)
            Issue.record("Expected animatedImageUnsupported")
        } catch let error as ImageConversionError {
            #expect(error == .animatedImageUnsupported(frameCount: 2))
        }

        let outputFiles = try FileManager.default.contentsOfDirectory(
            at: workspace.output,
            includingPropertiesForKeys: nil
        )
        #expect(outputFiles.isEmpty)
    }

    @Test("Batch conversion keeps successful items when another item fails")
    func batchIsolatesFailures() async throws {
        let workspace = try TestImageWorkspace()
        defer { workspace.remove() }

        let validURL = workspace.root.appendingPathComponent("valid.png")
        try TestImageFactory.writeStillImage(
            to: validURL,
            type: .png,
            width: 20,
            height: 20
        )
        let missingURL = workspace.root.appendingPathComponent("missing.png")

        let converter = ImageBatchConverter()
        let result = await converter.convert(
            [validURL, missingURL].map {
                ImageConversionRequest(
                    sourceURL: $0,
                    destinationDirectory: workspace.output,
                    outputFormat: .jpeg
                )
            },
            maxConcurrentConversions: 2
        )

        #expect(result.successes.count == 1)
        #expect(result.failures.count == 1)
        #expect(result.totalRequested == 2)
        #expect(result.wasCancelled == false)
    }
}

@Suite("Video to audio conversion models")
struct VideoAudioConversionModelTests {
    @Test("Video inputs are limited to native movie containers")
    func supportedVideoInputsAreExplicit() {
        #expect(AudioConversionEngine.supportedVideoInputExtensions == ["mov", "mp4", "m4v"])
    }

    @Test("Existing audio manifests decode as audio file sources")
    func legacyAudioManifestRemainsCompatible() throws {
        let id = UUID()
        let json = """
        [{
          "id":"\(id.uuidString)",
          "sourcePath":"/tmp/source.m4a",
          "sourceBytes":100,
          "status":"ready",
          "outputPath":null
        }]
        """

        let records = try JSONDecoder().decode(
            [PersistedConversionItem].self,
            from: Data(json.utf8)
        )

        #expect(records.count == 1)
        #expect(records[0].sourceKind == nil)
        #expect(records[0].duration == nil)
    }

    @Test("Audio conversion requests default to audio file sources")
    func requestDefaultsToAudioSource() {
        let request = AudioConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/source.wav"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            outputFormat: .wav,
            bitRate: .standard
        )

        #expect(request.sourceKind == .audioFile)
    }
}

private struct TestImageWorkspace {
    let root: URL
    let output: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageFormatConversionKitTests-\(UUID().uuidString)")
        output = root.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum TestImageFactory {
    static func properties(at url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    static func writeStillImage(
        to url: URL,
        type: UTType,
        width: Int,
        height: Int,
        alpha: CGFloat = 1,
        properties: [CFString: Any] = [:]
    ) throws {
        guard let image = makeImage(width: width, height: height, alpha: alpha) else {
            throw TestImageFactoryError.cannotCreateImage
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw TestImageFactoryError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageFactoryError.cannotFinalize
        }
    }

    static func writeAnimatedGIF(to url: URL, width: Int, height: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
            nil
        ) else {
            throw TestImageFactoryError.cannotCreateDestination
        }

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1
            ]
        ]

        for index in 0 ..< 2 {
            guard let image = makeImage(
                width: width,
                height: height,
                red: index == 0 ? 0.9 : 0.2,
                blue: index == 0 ? 0.2 : 0.9
            ) else {
                throw TestImageFactoryError.cannotCreateImage
            }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw TestImageFactoryError.cannotFinalize
        }
    }

    private static func makeImage(
        width: Int,
        height: Int,
        red: CGFloat = 0.85,
        blue: CGFloat = 0.25,
        alpha: CGFloat = 1
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(red: red, green: 0.45, blue: blue, alpha: alpha)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

private enum TestImageFactoryError: Error {
    case cannotCreateImage
    case cannotCreateDestination
    case cannotFinalize
}
