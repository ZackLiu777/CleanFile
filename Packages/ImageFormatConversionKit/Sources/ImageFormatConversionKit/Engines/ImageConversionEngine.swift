//
//  图片转换入口负责校验请求、预留输出路径，并把解码和编码交给后台任务。
//  工作层通过 Image I/O 检查格式、调整尺寸与元数据，最后提交临时文件。
//  路径冲突、取消和安全范围访问均在各自边界处理，不预先覆盖目标。
//  批量转换器与图片状态对象通过此入口提交请求和检查输出。
//  并发请求通过路径预留避免互相占用目标；调用方仍需处理源文件不可读等错误。
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 隔离输出路径预留状态，避免同一引擎内的并发请求选择相同目标。
public actor ImageConversionEngine {
    private var reservedDestinations = Set<URL>()

    /// 创建图片转换引擎；初始化时不访问输入文件。
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

    /// 在独立任务读取图片属性，并将调用任务的取消转发给该任务。
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

    /// 校验并预留输出路径，在独立任务中转换，结束时释放预留。
    /// 错误统一转换为 ImageConversionError，调用方取消也会传递给工作任务。
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

    /// 在分配输出路径前检查透明背景、质量、尺寸和系统格式支持。
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

    /// 按冲突策略选择路径并在 Actor 内预留；文件系统仍可能被外部进程改变。
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

    /// 移除路径分隔等非法字符及首尾空白、点号，空名称使用默认值。
    private static func sanitizedBaseName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:\0")
        let components = value.components(separatedBy: invalidCharacters)
        let joined = components.filter { !$0.isEmpty }.joined(separator: "-")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingDots = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return withoutTrailingDots.isEmpty ? "converted-image" : withoutTrailingDots
    }

    /// 保留已知转换错误，将任务取消和其他错误映射为公开错误类型。
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

/// 执行同步 Image I/O 工作；调用方负责放入独立任务和预留目标路径。
private enum ImageConversionWorker {
    private static let inputDefinitions: [(name: String, type: UTType)] = [
        ("JPG", .jpeg),
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

    /// 按实际内容类型而非扩展名检查输入是否属于允许的图片格式。
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

    /// 在安全范围内读取首帧属性、尺寸和内容类型，不缓存解码图像。
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

    /// 解码单帧图片并写入临时文件，再按冲突策略提交到预留路径。
    /// 在主要阶段检查取消，并在退出时清理未提交的临时文件。
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

    /// 读取首帧属性；转换只接受单帧图片。
    private static func properties(for source: CGImageSource) -> [CFString: Any]? {
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// 将缺失或非数字属性视为零，由上层校验必需尺寸。
    private static func number(_ value: Any?) -> NSNumber {
        if let number = value as? NSNumber {
            return number
        }
        return NSNumber(value: 0)
    }

    /// 根据隐私策略保留或移除元数据，并更新旋转后的方向和像素尺寸。
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

    /// 在 1024 像素方形画布中等比例居中，保留完整图像而不裁切。
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

    /// 以指定颜色填充透明区域，供不支持透明像素的输出格式使用。
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
