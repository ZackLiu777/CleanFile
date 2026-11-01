//
//  存储选择算法
//
//  提供大文件筛选和来源去重实现，并保留原始版本供比较。
//  大数据集只维护有限候选索引；来源比较使用标准化 URL 并保留原顺序。
//

import Foundation

/// Stable selection algorithms; original implementations are retained for regression comparisons.
nonisolated enum StorageSelectionAlgorithms {
    /// 完整排序后取前十项，作为小输入和比较基线。
    static func originalLargest(_ files: [ScannedFile]) -> [ScannedFile] {
        Array(files.sorted { $0.byteCount > $1.byteCount }.prefix(10))
    }

    /// 大输入仅维护最多十个索引，避免排序全部文件并保留原有大小排序语义。
    static func largest(_ files: [ScannedFile]) -> [ScannedFile] {
        guard files.count > 32 else { return originalLargest(files) }
        // Move only indexes: shifting complete file models repeatedly retains/releases URLs and strings.
        var indexes: [Int] = []
        indexes.reserveCapacity(10)
        for index in files.indices {
            let size = files[index].byteCount
            if indexes.count == 10, size <= files[indexes[9]].byteCount { continue }
            let insertion = indexes.firstIndex { size > files[$0].byteCount } ?? indexes.count
            indexes.insert(index, at: insertion)
            if indexes.count > 10 { indexes.removeLast() }
        }
        return indexes.map { files[$0] }
    }

    /// 以顺序查找标准化 URL 去重，保留首次出现的原始 URL。
    static func originalSources(_ sources: [URL]) -> [URL] {
        sources.reduce(into: [URL]()) { result, source in
            let normalized = source.standardizedFileURL
            if !result.contains(where: { $0.standardizedFileURL == normalized }) {
                result.append(source)
            }
        }
    }

    /// 使用集合按标准化 URL 去重，同时保留输入中首次出现的顺序。
    static func sources(_ sources: [URL]) -> [URL] {
        guard sources.count > 1 else { return sources }
        var seen: Set<URL> = []
        return sources.filter { seen.insert($0.standardizedFileURL).inserted }
    }
}
