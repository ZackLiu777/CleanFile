//
//  文件职责：集中定义 ImageBatchConverter 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import Foundation

/// 定义 `ImageBatchConverter` 的值语义数据与相关行为。
public struct ImageBatchConverter: Sendable {
    public typealias ProgressHandler = @Sendable (ImageBatchProgress) async -> Void

    private let engine: ImageConversionEngine

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(engine: ImageConversionEngine = ImageConversionEngine()) {
        self.engine = engine
    }

    /// 执行 `convert` 转换流程，并按当前配置生成输出结果。
    public func convert(
        _ requests: [ImageConversionRequest],
        maxConcurrentConversions: Int = 2,
        progress: ProgressHandler? = nil
    ) async -> ImageBatchConversionResult {
        guard !requests.isEmpty else {
            return ImageBatchConversionResult(
                successes: [],
                failures: [],
                totalRequested: 0,
                wasCancelled: Task.isCancelled
            )
        }

        let concurrencyLimit = min(max(maxConcurrentConversions, 1), requests.count)
        var indexedSuccesses: [(Int, ImageConversionResult)] = []
        var indexedFailures: [(Int, ImageConversionFailure)] = []
        var nextRequestIndex = 0
        var wasCancelled = Task.isCancelled

        await progress?(
            ImageBatchProgress(
                completed: 0,
                total: requests.count,
                succeeded: 0,
                failed: 0,
                lastSourceURL: nil
            )
        )

        await withTaskGroup(of: IndexedOutcome.self) { group in
            for _ in 0 ..< concurrencyLimit {
                let index = nextRequestIndex
                let request = requests[index]
                let conversionEngine = engine
                group.addTask {
                    await Self.convertOne(
                        index: index,
                        request: request,
                        engine: conversionEngine
                    )
                }
                nextRequestIndex += 1
            }

            while let outcome = await group.next() {
                let completedSourceURL: URL

                switch outcome {
                case let .success(index, result):
                    indexedSuccesses.append((index, result))
                    completedSourceURL = result.sourceURL

                case let .failure(index, failure):
                    indexedFailures.append((index, failure))
                    completedSourceURL = failure.sourceURL

                case let .cancelled(index, sourceURL):
                    wasCancelled = true
                    indexedFailures.append(
                        (
                            index,
                            ImageConversionFailure(sourceURL: sourceURL, error: .cancelled)
                        )
                    )
                    completedSourceURL = sourceURL
                }

                await progress?(
                    ImageBatchProgress(
                        completed: indexedSuccesses.count + indexedFailures.count,
                        total: requests.count,
                        succeeded: indexedSuccesses.count,
                        failed: indexedFailures.count,
                        lastSourceURL: completedSourceURL
                    )
                )

                if Task.isCancelled {
                    wasCancelled = true
                    group.cancelAll()
                } else if nextRequestIndex < requests.count {
                    let index = nextRequestIndex
                    let request = requests[index]
                    let conversionEngine = engine
                    group.addTask {
                        await Self.convertOne(
                            index: index,
                            request: request,
                            engine: conversionEngine
                        )
                    }
                    nextRequestIndex += 1
                }
            }
        }

        if nextRequestIndex < requests.count {
            wasCancelled = true
            for index in nextRequestIndex ..< requests.count {
                indexedFailures.append(
                    (
                        index,
                        ImageConversionFailure(
                            sourceURL: requests[index].sourceURL,
                            error: .cancelled
                        )
                    )
                )
            }
        }

        let successes = indexedSuccesses
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        let failures = indexedFailures
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        return ImageBatchConversionResult(
            successes: successes,
            failures: failures,
            totalRequested: requests.count,
            wasCancelled: wasCancelled
        )
    }

    /// 执行 `convertOne` 转换流程，并按当前配置生成输出结果。
    private static func convertOne(
        index: Int,
        request: ImageConversionRequest,
        engine: ImageConversionEngine
    ) async -> IndexedOutcome {
        do {
            let result = try await engine.convert(request)
            return .success(index: index, result: result)
        } catch let error as ImageConversionError {
            if error == .cancelled {
                return .cancelled(index: index, sourceURL: request.sourceURL)
            }
            return .failure(
                index: index,
                failure: ImageConversionFailure(
                    sourceURL: request.sourceURL,
                    error: error
                )
            )
        } catch is CancellationError {
            return .cancelled(index: index, sourceURL: request.sourceURL)
        } catch {
            return .failure(
                index: index,
                failure: ImageConversionFailure(
                    sourceURL: request.sourceURL,
                    error: .unexpected(error.localizedDescription)
                )
            )
        }
    }
}

/// 定义 `IndexedOutcome` 使用的有限状态或选项集合。
private enum IndexedOutcome: Sendable {
    case success(index: Int, result: ImageConversionResult)
    case failure(index: Int, failure: ImageConversionFailure)
    case cancelled(index: Int, sourceURL: URL)
}
