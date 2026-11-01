//
//  批量转换结果的排序策略：以原始请求索引恢复稳定的展示顺序。
//  根据数据规模、密度及顺序选择直接映射、位置表或原始排序。
//  输入索引不适合位置表时回退，避免优化改变结果语义。
//  批处理收集的结果携带原始位置，本类型仅调整结果顺序，不执行转换。
//  位置表优化只在输入符合条件时使用，其他情况保留通用排序路径。
//

/// 按原始请求索引恢复结果顺序，并针对规模较大的密集索引选择优化路径。
enum BatchResultOrderingCandidate {
    /// 使用排序作为通用基线，适用于稀疏或不规则索引。
    static func original<Value>(_ values: [(Int, Value)]) -> [Value] {
        values.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// 根据规模和索引分布选择优化方案；不适合时保留基线排序。
    static func preferred<Value>(_ values: [(Int, Value)], total: Int) -> [Value] {
        guard values.count >= 1_000, total >= values.count,
              total / 4 <= values.count else { return original(values) }
        var ascending = true
        var descending = true
        for index in 1..<values.count {
            ascending = ascending && values[index - 1].0 <= values[index].0
            descending = descending && values[index - 1].0 > values[index].0
            if !ascending && !descending { break }
        }
        if descending { return original(values) }
        return proposed(values, total: total)
    }

    /// 对有序结果直接映射，对密集乱序结果通过位置表恢复索引顺序。
    /// 越界或重复索引无法安全放入位置表时回退到基线。
    static func proposed<Value>(_ values: [(Int, Value)], total: Int) -> [Value] {
        guard values.count > 32, total >= values.count,
              total / 4 <= values.count else { return original(values) }
        // Completed batches are often already ordered. Avoid allocating a table for those runs.
        var ascending = true
        var descending = true
        for index in 1..<values.count {
            ascending = ascending && values[index - 1].0 <= values[index].0
            descending = descending && values[index - 1].0 > values[index].0
            if !ascending && !descending { break }
        }
        if ascending { return values.map(\.1) }
        if descending { return values.reversed().map(\.1) }
        var positions = Array(repeating: -1, count: total)
        for (position, pair) in values.enumerated() {
            guard positions.indices.contains(pair.0), positions[pair.0] == -1 else {
                return original(values)
            }
            positions[pair.0] = position
        }
        var result: [Value] = []
        result.reserveCapacity(values.count)
        for position in positions where position >= 0 { result.append(values[position].1) }
        return result
    }
}
