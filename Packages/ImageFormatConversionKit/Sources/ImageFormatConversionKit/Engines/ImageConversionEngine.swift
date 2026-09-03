//
//  文件职责：实现 ImageConversion 底层处理流程，并向上层提供稳定入口。
//  所属模块：ImageFormatConversionKit。
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 使用 Actor 隔离 `ImageConversionEngine` 的可变状态，确保并发访问安全。
public actor ImageConversionEngine {
    private var reservedDestinations = Set<URL>()

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init() {}

    public static var supportedOutputFormats: [ImageOutputFormat] {
        ImageConversionWorker.supportedOutputFormats
    }

    public static var supportedInputFormatNames: [String] {
        ImageConversionWorker.supportedInputFormatNames
    }

    public static var supportedInputContentTypes: [UTType] {
        ImageConversionWorker.supportedInputContentTypes
    }

    /// 执行 `inspect` 分析流程，在遵守文件访问边界的前提下生成结果。
    public func inspect(_ sourceURL: URL) async throws -> ImageAssetInfo {
        let worker = Task.detached(priority: .utility) {
            try ImageConversionWorker.inspect(sourceURL)
        }

        do {
            return try await withTaskCancellationHandler(
                operation: { try await worker.value },
                onCancel: { worker.cancel() }
            )
        } catch {
            throw Self.normalized(error)
        }
    }

    /// 执行 `convert` 转换流程，并按当前配置生成输出结果。
    public func convert(_ request: ImageConversionRequest) async throws -> ImageConversionResult {
        try validate(request)
        let destinationURL = try reserveDestination(for: request)

        defer {
            reservedDestinations.remove(destinationURL.standardizedFileURL)
        }

        let worker = Task.detached(priority: .userInitiated) {
            try ImageConversionWorker.convert(request, destinationURL: destinationURL)
        }

        do {
            return try await withTaskCancellationHandler(
                operation: { try await worker.value },
                onCancel: { worker.cancel() }
            )
        } catch {
            throw Self.normalized(error)
        }
    }

    /// 验证 `validate` 所需条件，并阻止无效状态继续进入后续流程。
    private func validate(_ request: ImageConversionRequest) throws {
        guard request.background != .transparent || request.outputFormat.supportsTransparentBackground else {
            throw ImageConversionError.unsupportedOutputFormat(request.outputFormat)
        }
        guard (0 ... 1).contains(request.quality) else {
            throw ImageConversionError.invalidQuality(request.quality)
        }

        if case let .fit(maxPixelDimension) = request.resizePolicy,
           maxPixelDimension <= 0 {
            throw ImageConversionError.invalidMaximumPixelDimension(maxPixelDimension)
        }

        guard Self.supportedOutputFormats.contains(request.outputFormat) else {
            throw ImageConversionError.unsupportedOutputFormat(request.outputFormat)
        }
    }

    /// 封装 `reserveDestination` 对应的局部行为，供当前类型在统一入口下复用。
    private func reserveDestination(for request: ImageConversionRequest) throws -> URL {
        let fileManager = FileManager()
        let directory = request.destinationDirectory.standardizedFileURL
        let didAccessDirectory = directory.startAccessingSecurityScopedResource()
        defer {
            if didAccessDirectory {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ImageConversionError.cannotCreateDestination(directory)
        }

        let rawBaseName = request.preferredBaseName
            ?? request.sourceURL.deletingPathExtension().lastPathComponent
        let baseName = Self.sanitizedBaseName(rawBaseName)
        let directURL = directory
            .appendingPathComponent(baseName, isDirectory: false)
            .appendingPathExtension(request.outputFormat.fileExtension)
            .standardizedFileURL

        switch request.collisionPolicy {
        case .overwrite:
            guard !reservedDestinations.contains(directURL) else {
                throw ImageConversionError.destinationBusy(directURL)
            }
            reservedDestinations.insert(directURL)
            return directURL

        case .fail:
            guard !reservedDestinations.contains(directURL) else {
                throw ImageConversionError.destinationBusy(directURL)
            }
            guard !fileManager.fileExists(atPath: directURL.path) else {
                throw ImageConversionError.destinationExists(directURL)
            }
            reservedDestinations.insert(directURL)
            return directURL

        case .makeUnique:
            for suffix in 0 ... 9_999 {
                let candidateBaseName = suffix == 0 ? baseName : "\(baseName)-\(suffix)"
                let candidateURL = directory
                    .appendingPathComponent(candidateBaseName, isDirectory: false)
                    .appendingPathExtension(request.outputFormat.fileExtension)
                    .standardizedFileURL

                guard !reservedDestinations.contains(candidateURL) else { continue }
                guard !fileManager.fileExists(atPath: candidateURL.path) else { continue }

                reservedDestinations.insert(candidateURL)
                return candidateURL
            }

            throw ImageConversionError.cannotReserveOutputName(directURL)
        }
    }

    /// 封装 `sanitizedBaseName` 对应的局部行为，供当前类型在统一入口下复用。
    private static func sanitizedBaseName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:\0")
        let components = value.components(separatedBy: invalidCharacters)
        let joined = components.filter { !$0.isEmpty }.joined(separator: "-")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingDots = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return withoutTrailingDots.isEmpty ? "converted-image" : withoutTrailingDots
    }

    /// 封装 `normalized` 对应的局部行为，供当前类型在统一入口下复用。
    private static func normalized(_ error: Error) -> ImageConversionError {
        if let conversionError = error as? ImageConversionError {
            return conversionError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .unexpected(error.localizedDescription)
    }
}

/// 定义 `ImageConversionWorker` 使用的有限状态或选项集合。
private enum ImageConversionWorker {
    private static let inputDefinitions: [(name: String, type: UTType)] = [
        ("JPEG", .jpeg),
        ("PNG", .png),
        ("HEIC", .heic),
        ("HEIF", .heif),
        ("TIFF", .tiff),
        ("WebP", .webP),
        ("GIF (Static)", .gif),
        ("BMP", .bmp),
        ("DNG / ProRAW / RAW", .rawImage)
    ]

    private static var sourceTypes: [UTType] {
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as NSArray)
            .compactMap { $0 as? String }
        return identifiers.compactMap(UTType.init)
    }

    static var supportedInputFormatNames: [String] {
        inputDefinitions.compactMap { definition in
            sourceTypes.contains(where: { $0.conforms(to: definition.type) })
                ? definition.name
                : nil
        }
    }

    static var supportedInputContentTypes: [UTType] {
        inputDefinitions.compactMap { definition in
            sourceTypes.contains(where: { $0.conforms(to: definition.type) })
                ? definition.type
                : nil
        }
    }

    /// 判断 `supportsInput` 条件是否成立，供调用方选择正确的处理分支。
    private static func supportsInput(_ identifier: String?) -> Bool {
        guard let identifier, let type = UTType(identifier) else { return false }
        return inputDefinitions.contains { type.conforms(to: $0.type) }
    }

    static var supportedOutputFormats: [ImageOutputFormat] {
        let identifiers = (CGImageDestinationCopyTypeIdentifiers() as NSArray)
            .compactMap { $0 as? String }
        let identifierSet = Set(identifiers)
        return ImageOutputFormat.allCases.filter {
            identifierSet.contains($0.typeIdentifier)
        }
    }

    /// 执行 `inspect` 分析流程，在遵守文件访问边界的前提下生成结果。
    static func inspect(_ sourceURL: URL) throws -> ImageAssetInfo {
        try Task.checkCancellation()

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard (try? sourceURL.checkResourceIsReachable()) == true else {
            throw ImageConversionError.sourceNotReachable(sourceURL)
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, options) else {
            throw ImageConversionError.cannotOpenSource(sourceURL)
        }

        guard let properties = properties(for: source) else {
            throw ImageConversionError.invalidImageProperties(sourceURL)
        }

        let width = number(properties[kCGImagePropertyPixelWidth]).intValue
        let height = number(properties[kCGImagePropertyPixelHeight]).intValue
        guard width > 0, height > 0 else {
            throw ImageConversionError.invalidImageProperties(sourceURL)
        }

        let resourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues?.fileSize ?? 0)
        let typeIdentifier = CGImageSourceGetType(source).map { $0 as String }
        guard supportsInput(typeIdentifier) else {
            throw ImageConversionError.unsupportedInputFormat(sourceURL)
        }
        let hasAlpha = number(properties[kCGImagePropertyHasAlpha]).boolValue

        return ImageAssetInfo(
            sourceURL: sourceURL,
            typeIdentifier: typeIdentifier,
            pixelWidth: width,
            pixelHeight: height,
            frameCount: CGImageSourceGetCount(source),
            fileSizeBytes: fileSize,
            hasAlpha: hasAlpha
        )
    }

    /// 执行 `convert` 转换流程，并按当前配置生成输出结果。
    static func convert(
        _ request: ImageConversionRequest,
        destinationURL: URL
    ) throws -> ImageConversionResult {
        let performanceID = ConversionPerformance.begin("Conversion Image Total")
        defer { ConversionPerformance.end("Conversion Image Total", id: performanceID) }
        let clock = ContinuousClock()
        let startedAt = clock.now
        let fileManager = FileManager()
        let sourceURL = request.sourceURL
        let destinationDirectory = request.destinationDirectory.standardizedFileURL

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        let didAccessDirectory = destinationDirectory.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            if didAccessDirectory {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        try Task.checkCancellation()
        guard (try? sourceURL.checkResourceIsReachable()) == true else {
            throw ImageConversionError.sourceNotReachable(sourceURL)
        }

        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ImageConversionError.cannotCreateDestination(destinationDirectory)
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions) else {
            throw ImageConversionError.cannotOpenSource(sourceURL)
        }

        let sourceTypeIdentifier = CGImageSourceGetType(source).map { $0 as String }
        guard supportsInput(sourceTypeIdentifier) else {
            throw ImageConversionError.unsupportedInputFormat(sourceURL)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == 1 else {
            throw ImageConversionError.animatedImageUnsupported(frameCount: frameCount)
        }

        guard let sourceProperties = properties(for: source) else {
            throw ImageConversionError.invalidImageProperties(sourceURL)
        }

        let sourceWidth = number(sourceProperties[kCGImagePropertyPixelWidth]).intValue
        let sourceHeight = number(sourceProperties[kCGImagePropertyPixelHeight]).intValue
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ImageConversionError.invalidImageProperties(sourceURL)
        }

        let sourceValuesBeforeConversion = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let sourceBytesBeforeConversion = Int64(sourceValuesBeforeConversion?.fileSize ?? 0)

        try Task.checkCancellation()
        let sourceMaxDimension = max(sourceWidth, sourceHeight)
        let requestedMaxDimension: Int
        switch request.resizePolicy {
        case .original:
            requestedMaxDimension = sourceMaxDimension
        case let .fit(maxPixelDimension):
            requestedMaxDimension = min(sourceMaxDimension, maxPixelDimension)
        case .square1024:
            requestedMaxDimension = min(sourceMaxDimension, 1024)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: requestedMaxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        let decodeID = ConversionPerformance.begin("Conversion Image Decode")
        guard var decodedImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            ConversionPerformance.end("Conversion Image Decode", id: decodeID)
            throw ImageConversionError.cannotDecode(sourceURL)
        }
        ConversionPerformance.end("Conversion Image Decode", id: decodeID)

        if request.resizePolicy == .square1024 {
            let color: ImageFlattenColor? = request.background == nil ? .white : request.background?.color
            decodedImage = try squareCanvas(decodedImage, color: color)
        } else if let background = request.background {
            if let color = background.color {
                decodedImage = try flattened(decodedImage, color: color)
            }
        } else if request.outputFormat.requiresOpaquePixels {
            decodedImage = try flattened(decodedImage, color: request.flattenColor)
        }

        try Task.checkCancellation()
        let temporaryURL = destinationDirectory
            .appendingPathComponent(".image-conversion-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("tmp")

        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            request.outputFormat.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.cannotCreateDestination(destinationURL)
        }

        let outputProperties = destinationProperties(
            sourceProperties: sourceProperties,
            request: request,
            outputImage: decodedImage
        )
        let encodeID = ConversionPerformance.begin("Conversion Image Encode")
        CGImageDestinationAddImage(destination, decodedImage, outputProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            ConversionPerformance.end("Conversion Image Encode", id: encodeID)
            throw ImageConversionError.cannotFinalizeDestination(destinationURL)
        }
        ConversionPerformance.end("Conversion Image Encode", id: encodeID)

        try Task.checkCancellation()
        let commitID = ConversionPerformance.begin("Conversion Output Commit")
        defer { ConversionPerformance.end("Conversion Output Commit", id: commitID) }
        do {
            let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
            if destinationExists {
                switch request.collisionPolicy {
                case .overwrite:
                    _ = try fileManager.replaceItemAt(
                        destinationURL,
                        withItemAt: temporaryURL,
                        backupItemName: nil,
                        options: []
                    )
                case .fail, .makeUnique:
                    throw ImageConversionError.destinationExists(destinationURL)
                }
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch let error as ImageConversionError {
            throw error
        } catch {
            throw ImageConversionError.fileCommitFailed(error.localizedDescription)
        }

        let outputValues = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])

        return ImageConversionResult(
            sourceURL: sourceURL,
            outputURL: destinationURL,
            outputFormat: request.outputFormat,
            sourceBytes: sourceBytesBeforeConversion,
            outputBytes: Int64(outputValues?.fileSize ?? 0),
            pixelWidth: decodedImage.width,
            pixelHeight: decodedImage.height,
            duration: startedAt.duration(to: clock.now)
        )
    }

    /// 封装 `properties` 对应的局部行为，供当前类型在统一入口下复用。
    private static func properties(for source: CGImageSource) -> [CFString: Any]? {
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// 封装 `number` 对应的局部行为，供当前类型在统一入口下复用。
    private static func number(_ value: Any?) -> NSNumber {
        if let number = value as? NSNumber {
            return number
        }
        return NSNumber(value: 0)
    }

    /// 封装 `destinationProperties` 对应的局部行为，供当前类型在统一入口下复用。
    private static func destinationProperties(
        sourceProperties: [CFString: Any],
        request: ImageConversionRequest,
        outputImage: CGImage
    ) -> [CFString: Any] {
        var properties: [CFString: Any]

        switch request.metadataPolicy {
        case .preserve:
            properties = sourceProperties
        case .removeGPS:
            properties = sourceProperties
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        case .removeAll:
            properties = [:]
        }

        if request.metadataPolicy != .removeAll {
            properties[kCGImagePropertyOrientation] = 1
            properties[kCGImagePropertyPixelWidth] = outputImage.width
            properties[kCGImagePropertyPixelHeight] = outputImage.height

            if var tiffProperties = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiffProperties[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiffProperties
            }

            if var exifProperties = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exifProperties[kCGImagePropertyExifPixelXDimension] = outputImage.width
                exifProperties[kCGImagePropertyExifPixelYDimension] = outputImage.height
                properties[kCGImagePropertyExifDictionary] = exifProperties
            }
        }

        if request.outputFormat.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = request.quality
        }

        return properties
    }

    /// Preserve the entire oriented image instead of stretching or silently cropping it.
    private static func squareCanvas(_ image: CGImage, color: ImageFlattenColor?) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageConversionError.cannotFlattenTransparency }
        if let color {
            context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        } else {
            context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        let scale = 1024 / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
        guard let output = context.makeImage() else { throw ImageConversionError.cannotFlattenTransparency }
        return output
    }

    /// 封装 `flattened` 对应的局部行为，供当前类型在统一入口下复用。
    private static func flattened(
        _ image: CGImage,
        color: ImageFlattenColor
    ) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageConversionError.cannotFlattenTransparency
        }

        context.setFillColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let flattenedImage = context.makeImage() else {
            throw ImageConversionError.cannotFlattenTransparency
        }
        return flattenedImage
    }
}
