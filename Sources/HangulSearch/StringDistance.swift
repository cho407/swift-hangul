import Foundation

public enum SimilarityDistanceAlgorithm: String, Codable, Sendable {
    case levenshtein
    /// Restricted Damerau-Levenshtein: adjacent transposition costs one edit.
    case optimalStringAlignment
}

enum StringDistance {
    static func distance(
        _ lhs: [UnicodeScalar], _ rhs: [UnicodeScalar],
        algorithm: SimilarityDistanceAlgorithm = .levenshtein,
        cancellationCheck: (() throws -> Void)? = nil
    ) rethrows -> Int {
        try cancellationCheck?()
        let rows = lhs.count >= rhs.count ? lhs : rhs
        let columns = lhs.count >= rhs.count ? rhs : lhs
        guard !columns.isEmpty else { return rows.count }
        if rows == columns { return 0 }
        var previous = Array(0...columns.count)
        var current = previous
        var beforePrevious = algorithm == .optimalStringAlignment ? previous : []
        for i in 1...rows.count {
            try cancellationCheck?()
            current[0] = i
            for j in 1...columns.count {
                if j.isMultiple(of: 256) { try cancellationCheck?() }
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (rows[i - 1] == columns[j - 1] ? 0 : 1))
                if algorithm == .optimalStringAlignment, i > 1, j > 1,
                   rows[i - 1] == columns[j - 2], rows[i - 2] == columns[j - 1] {
                    current[j] = min(current[j], beforePrevious[j - 2] + 1)
                }
            }
            if algorithm == .optimalStringAlignment { swap(&beforePrevious, &previous) }
            swap(&previous, &current)
        }
        return previous[columns.count]
    }

    static func weightedDistance(
        _ lhs: [UnicodeScalar], _ rhs: [UnicodeScalar],
        substitutionCost: (UnicodeScalar, UnicodeScalar) -> Double,
        cancellationCheck: (() throws -> Void)? = nil
    ) rethrows -> Double {
        try cancellationCheck?()
        let rows = lhs.count >= rhs.count ? lhs : rhs
        let columns = lhs.count >= rhs.count ? rhs : lhs
        guard !columns.isEmpty else { return Double(rows.count) }
        if rows == columns { return 0 }
        var previous = (0...columns.count).map(Double.init)
        var current = previous
        for i in 1...rows.count {
            try cancellationCheck?()
            current[0] = Double(i)
            for j in 1...columns.count {
                if j.isMultiple(of: 256) { try cancellationCheck?() }
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + substitutionCost(rows[i - 1], columns[j - 1]))
            }
            swap(&previous, &current)
        }
        return previous[columns.count]
    }
}
