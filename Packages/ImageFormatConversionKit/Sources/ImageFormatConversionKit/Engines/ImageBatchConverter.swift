//
//  批量协调图片转换，以固定上限提交任务并汇总每一项结果。
//  完成顺序可能不同于输入顺序，返回前按原始索引恢复顺序。
//  取消后停止补充任务，保留已完成结果，并为未开始的请求记录取消。
//  上层提供图片请求、并发上限和可选进度回调，单项工作由图片引擎执行。
//  成功与失败分别按请求顺序返回，调用方可根据取消标记区分未完成的批次。
//

import Foundation

/// 使用共享图片引擎执行有界并发批处理，并分别汇总成功和失败。
public struct ImageBatchConverter: Sendable {
    public typealias ProgressHandler = @Sendable (ImageBatchProgress) async -> Void

    private let engine: ImageConversionEngine

    /// 保存图片引擎供批处理复用；并发上限由每次转换调用指定。
    public init(engine: ImageConversionEngine = ImageConversionEngine()) {
        self.engine = engine
    }

    /// 初始填满并发窗口，之后每完成一项再补充一项。
    /// 取消时停止补充并取消子任务；结果按输入顺序排列，进度按实际完成报告。
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

        let successes = BatchResultOrderingCandidate.preferred(indexedSuccesses, total: requests.count)
        let failures = BatchResultOrderingCandidate.preferred(indexedFailures, total: requests.count)

        return ImageBatchConversionResult(
            successes: successes,
            failures: failures,
            totalRequested: requests.count,
            wasCancelled: wasCancelled
        )
    }

    /// 将单项错误转换为可汇总结果，并将取消与普通失败区分。
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

/// 记录原始索引，以便异步完成后恢复请求顺序。
private enum IndexedOutcome: Sendable {
    case success(index: Int, result: ImageConversionResult)
    case failure(index: Int, failure: ImageConversionFailure)
    case cancelled(index: Int, sourceURL: URL)
}
