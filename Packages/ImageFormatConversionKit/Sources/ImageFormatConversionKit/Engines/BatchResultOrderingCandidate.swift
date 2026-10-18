/// Preserve the sort baseline and only promote dense ascending or unordered batches.
enum BatchResultOrderingCandidate {
    static func original<Value>(_ values: [(Int, Value)]) -> [Value] {
        values.sorted { $0.0 < $1.0 }.map(\.1)
    }

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
