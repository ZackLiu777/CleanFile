import Foundation

/// Median selection with a retained sorting baseline for unsuitable distributions.
nonisolated enum MediaCalibrationMedianCandidate {
    /// Retained sort core, exposed internally so both timing paths cross the
    /// same module boundary.
    static func baselineCoefficient(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        return median(ofSorted: values.sorted())
    }

    /// Only promote the large, unordered scenario covered by the comparison.
    static func preferredCoefficient(_ values: [Double]) -> Double? {
        guard values.count >= 1_000, !looksRunOrdered(values), values.allSatisfy(\.isFinite) else {
            return baselineCoefficient(values)
        }
        return coefficient(values)
    }

    static func coefficient(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        // Sorting is cheaper for small samples. Keep the exact legacy treatment
        // of non-finite values rather than imposing a new ordering or clamp.
        guard values.count >= 128, !looksRunOrdered(values), values.allSatisfy(\.isFinite) else {
            return baselineCoefficient(values)
        }

        var work = values
        let middle = work.count / 2
        var lower = 0
        var upper = work.count - 1
        var budget = 2 * (Int.bitWidth - work.count.leadingZeroBitCount)
        while lower < upper {
            guard budget > 0 else {
                // Bound adversarial pivot sequences by O(n log n), preserving
                // the original answer instead of accepting quadratic work.
                work.sort()
                return median(ofSorted: work)
            }
            budget -= 1
            let center = lower + (upper - lower) / 2
            let a = work[lower], b = work[center], c = work[upper]
            let pivot = max(min(a, b), min(max(a, b), c))
            var less = lower
            var cursor = lower
            var greater = upper
            while cursor <= greater {
                if work[cursor] < pivot {
                    work.swapAt(less, cursor)
                    less += 1
                    cursor += 1
                } else if work[cursor] > pivot {
                    work.swapAt(cursor, greater)
                    greater -= 1
                } else {
                    cursor += 1
                }
            }
            if middle < less {
                upper = less - 1
            } else if middle > greater {
                lower = greater + 1
            } else {
                break
            }
        }

        if work.count.isMultiple(of: 2) {
            // The selected middle partitions the lower half; its maximum is
            // the lower median, so a second selection/sort is unnecessary.
            let lowerMedian = work[..<middle].max() ?? work[0]
            return (lowerMedian + work[middle]) / 2
        }
        return work[middle]
    }

    private static func looksRunOrdered(_ values: [Double]) -> Bool {
        // Swift's adaptive sort is already efficient on runs. A fixed-size
        // probe chooses the old sort for those shapes; misclassification only
        // changes performance, never which numerical result is returned.
        let stride = (values.count - 1) / 8
        var previous = values[0]
        var ascending = true
        var descending = true
        var mountain = true
        for probe in 1...8 {
            let current = values[probe == 8 ? values.count - 1 : probe * stride]
            ascending = ascending && previous <= current
            descending = descending && previous >= current
            mountain = mountain && (probe <= 4 ? previous <= current : previous >= current)
            previous = current
        }
        return ascending || descending || mountain
    }

    private static func median(ofSorted values: [Double]) -> Double {
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }
}
