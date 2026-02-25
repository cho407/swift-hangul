import Foundation
import HangulCore

public struct SimilarityWeights: Codable, Sendable, Equatable {
    public var editDistance: Double
    public var jaccard: Double
    public var keyboard: Double
    public var jamo: Double
    public var prefixBonus: Double
    public var exactBonus: Double

    public static let `default` = SimilarityWeights(
        editDistance: 0.35,
        jaccard: 0.25,
        keyboard: 0.15,
        jamo: 0.25,
        prefixBonus: 0.08,
        exactBonus: 0.12
    )

    public init(
        editDistance: Double = 0.35,
        jaccard: Double = 0.25,
        keyboard: Double = 0.15,
        jamo: Double = 0.25,
        prefixBonus: Double = 0.08,
        exactBonus: Double = 0.12
    ) {
        self.editDistance = editDistance
        self.jaccard = jaccard
        self.keyboard = keyboard
        self.jamo = jamo
        self.prefixBonus = prefixBonus
        self.exactBonus = exactBonus
    }
}

public struct SimilarityOptions: Codable, Sendable, Equatable {
    public var limit: Int
    public var ngramSize: Int
    public var candidateLimitPerVariant: Int
    public var includeLayoutVariants: Bool
    public var minimumScore: Double
    public var weights: SimilarityWeights

    public static let `default` = SimilarityOptions()

    public init(
        limit: Int = 20,
        ngramSize: Int = 2,
        candidateLimitPerVariant: Int = 1_200,
        includeLayoutVariants: Bool = true,
        minimumScore: Double = 0.2,
        weights: SimilarityWeights = .default
    ) {
        self.limit = limit
        self.ngramSize = max(1, ngramSize)
        self.candidateLimitPerVariant = max(1, candidateLimitPerVariant)
        self.includeLayoutVariants = includeLayoutVariants
        self.minimumScore = min(1, max(0, minimumScore))
        self.weights = weights
    }
}

public struct SimilarityScoreBreakdown: Sendable {
    public let editDistanceSimilarity: Double
    public let jaccardSimilarity: Double
    public let keyboardSimilarity: Double
    public let jamoSimilarity: Double
    public let weightedCoreScore: Double
    public let prefixBonus: Double
    public let exactBonus: Double
    public let totalScore: Double

    public init(
        editDistanceSimilarity: Double = 0,
        jaccardSimilarity: Double = 0,
        keyboardSimilarity: Double = 0,
        jamoSimilarity: Double = 0,
        weightedCoreScore: Double = 0,
        prefixBonus: Double = 0,
        exactBonus: Double = 0,
        totalScore: Double
    ) {
        self.editDistanceSimilarity = editDistanceSimilarity
        self.jaccardSimilarity = jaccardSimilarity
        self.keyboardSimilarity = keyboardSimilarity
        self.jamoSimilarity = jamoSimilarity
        self.weightedCoreScore = weightedCoreScore
        self.prefixBonus = prefixBonus
        self.exactBonus = exactBonus
        self.totalScore = totalScore
    }
}

public struct ScoredSearchResult<Item> {
    public let item: Item
    public let score: Double
    public let breakdown: SimilarityScoreBreakdown
    public let matchedQuery: String
    public let matchedKey: String

    public init(item: Item, score: Double, matchedQuery: String, matchedKey: String) {
        self.item = item
        self.score = score
        self.breakdown = SimilarityScoreBreakdown(totalScore: score)
        self.matchedQuery = matchedQuery
        self.matchedKey = matchedKey
    }

    public init(
        item: Item,
        breakdown: SimilarityScoreBreakdown,
        matchedQuery: String,
        matchedKey: String
    ) {
        self.item = item
        self.score = breakdown.totalScore
        self.breakdown = breakdown
        self.matchedQuery = matchedQuery
        self.matchedKey = matchedKey
    }
}

public struct SimilarityExplanationDetail: Sendable {
    public let normalizedQuery: String
    public let normalizedTarget: String
    public let choseongQuery: String
    public let choseongTarget: String
    public let jamoQuery: String
    public let jamoTarget: String
    public let editDistance: Int
    public let jamoEditDistance: Int
    public let keyboardDistance: Double
    public let jaccardIntersectionCount: Int
    public let jaccardUnionCount: Int

    public init(
        normalizedQuery: String,
        normalizedTarget: String,
        choseongQuery: String,
        choseongTarget: String,
        jamoQuery: String,
        jamoTarget: String,
        editDistance: Int,
        jamoEditDistance: Int,
        keyboardDistance: Double,
        jaccardIntersectionCount: Int,
        jaccardUnionCount: Int
    ) {
        self.normalizedQuery = normalizedQuery
        self.normalizedTarget = normalizedTarget
        self.choseongQuery = choseongQuery
        self.choseongTarget = choseongTarget
        self.jamoQuery = jamoQuery
        self.jamoTarget = jamoTarget
        self.editDistance = editDistance
        self.jamoEditDistance = jamoEditDistance
        self.keyboardDistance = keyboardDistance
        self.jaccardIntersectionCount = jaccardIntersectionCount
        self.jaccardUnionCount = jaccardUnionCount
    }
}

public struct ExplainedSearchResult<Item> {
    public let item: Item
    public let score: Double
    public let breakdown: SimilarityScoreBreakdown
    public let matchedQuery: String
    public let matchedKey: String
    public let detail: SimilarityExplanationDetail

    public init(
        item: Item,
        breakdown: SimilarityScoreBreakdown,
        matchedQuery: String,
        matchedKey: String,
        detail: SimilarityExplanationDetail
    ) {
        self.item = item
        self.score = breakdown.totalScore
        self.breakdown = breakdown
        self.matchedQuery = matchedQuery
        self.matchedKey = matchedKey
        self.detail = detail
    }
}

enum SimilarityScorer {
    static func queryVariants(for query: String, includeLayoutVariants: Bool) -> [String] {
        var seen: Set<String> = []
        var variants: [String] = []
        variants.reserveCapacity(3)

        func appendVariant(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if seen.insert(normalized).inserted {
                variants.append(normalized)
            }
        }

        appendVariant(query)
        if includeLayoutVariants {
            appendVariant(Hangul.convertQwertyToHangul(query))
            appendVariant(Hangul.convertHangulToQwerty(query))
        }

        return variants
    }

    static func score(
        query: String,
        target: String,
        queryChoseong: String,
        targetChoseong: String,
        options: SimilarityOptions
    ) -> SimilarityScoreBreakdown {
        let explained = explain(
            query: query,
            target: target,
            queryChoseong: queryChoseong,
            targetChoseong: targetChoseong,
            options: options
        )
        return explained.breakdown
    }

    static func explain(
        query: String,
        target: String,
        queryChoseong: String,
        targetChoseong: String,
        options: SimilarityOptions
    ) -> (breakdown: SimilarityScoreBreakdown, detail: SimilarityExplanationDetail) {
        let lhs = canonical(query)
        let rhs = canonical(target)
        if lhs.isEmpty || rhs.isEmpty {
            let emptyDetail = SimilarityExplanationDetail(
                normalizedQuery: lhs,
                normalizedTarget: rhs,
                choseongQuery: "",
                choseongTarget: "",
                jamoQuery: "",
                jamoTarget: "",
                editDistance: max(lhs.count, rhs.count),
                jamoEditDistance: 0,
                keyboardDistance: Double(max(lhs.count, rhs.count)),
                jaccardIntersectionCount: 0,
                jaccardUnionCount: 0
            )
            return (SimilarityScoreBreakdown(totalScore: 0), emptyDetail)
        }

        let choseongLHS = queryChoseong.isEmpty ? lhs : canonical(queryChoseong)
        let choseongRHS = targetChoseong.isEmpty ? rhs : canonical(targetChoseong)

        let editDistance = levenshteinDistance(lhs, rhs)
        let editSimilarity = normalizedSimilarity(distance: editDistance, maxLength: max(lhs.count, rhs.count))

        let jaccardStats = jaccardNgramStats(choseongLHS, choseongRHS, n: options.ngramSize)
        let keyboard = keyboardProximityStats(lhs, rhs)
        let jamoStats = jamoStats(lhs, rhs)

        let weights = options.weights
        let weightSum = max(
            0.000_001,
            weights.editDistance + weights.jaccard + weights.keyboard + weights.jamo
        )

        let weightedCore = (
            (editSimilarity * weights.editDistance) +
            (jaccardStats.similarity * weights.jaccard) +
            (keyboard.similarity * weights.keyboard) +
            (jamoStats.similarity * weights.jamo)
        ) / weightSum

        let exactBonus = rhs == lhs ? weights.exactBonus : 0
        let prefixBonus = (exactBonus == 0 && (rhs.hasPrefix(lhs) || choseongRHS.hasPrefix(choseongLHS)))
            ? weights.prefixBonus
            : 0

        let total = min(1, max(0, weightedCore + exactBonus + prefixBonus))
        let breakdown = SimilarityScoreBreakdown(
            editDistanceSimilarity: editSimilarity,
            jaccardSimilarity: jaccardStats.similarity,
            keyboardSimilarity: keyboard.similarity,
            jamoSimilarity: jamoStats.similarity,
            weightedCoreScore: weightedCore,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus,
            totalScore: total
        )

        let detail = SimilarityExplanationDetail(
            normalizedQuery: lhs,
            normalizedTarget: rhs,
            choseongQuery: choseongLHS,
            choseongTarget: choseongRHS,
            jamoQuery: jamoStats.queryJamo,
            jamoTarget: jamoStats.targetJamo,
            editDistance: editDistance,
            jamoEditDistance: jamoStats.distance,
            keyboardDistance: keyboard.distance,
            jaccardIntersectionCount: jaccardStats.intersectionCount,
            jaccardUnionCount: jaccardStats.unionCount
        )

        return (breakdown, detail)
    }

    static func coarseSimilarity(
        query: String,
        choseongQuery: String,
        key: String,
        choseongKey: String
    ) -> Double {
        let lhs = choseongQuery.isEmpty ? query : choseongQuery
        let rhs = choseongQuery.isEmpty ? key : choseongKey
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        let overlap = tokenOverlap(lhs, rhs)
        if overlap == 0 {
            return 0
        }

        let maxLength = max(lhs.count, rhs.count)
        let lengthScore = max(
            0,
            1 - (Double(abs(lhs.count - rhs.count)) / Double(max(1, maxLength)))
        )

        var score = (overlap * 0.65) + (lengthScore * 0.35)
        if lhs.first == rhs.first {
            score += 0.1
        }
        return min(1, score)
    }

    private static func canonical(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func jamoStats(_ lhs: String, _ rhs: String) -> (queryJamo: String, targetJamo: String, distance: Int, similarity: Double) {
        let disassembleOptions = DisassembleOptions(
            decomposeDoubleVowels: true,
            decomposeDoubleFinals: true,
            preserveNonHangul: false
        )

        let lhsJamo = Hangul.disassemble(lhs, options: disassembleOptions)
        let rhsJamo = Hangul.disassemble(rhs, options: disassembleOptions)

        if lhsJamo.isEmpty || rhsJamo.isEmpty {
            let distance = levenshteinDistance(lhs, rhs)
            let similarity = normalizedSimilarity(distance: distance, maxLength: max(lhs.count, rhs.count))
            return (lhsJamo, rhsJamo, distance, similarity)
        }

        let distance = levenshteinDistance(lhsJamo, rhsJamo)
        let similarity = normalizedSimilarity(distance: distance, maxLength: max(lhsJamo.count, rhsJamo.count))
        return (lhsJamo, rhsJamo, distance, similarity)
    }

    private static func jaccardNgramSimilarity(_ lhs: String, _ rhs: String, n: Int) -> Double {
        jaccardNgramStats(lhs, rhs, n: n).similarity
    }

    private static func jaccardNgramStats(_ lhs: String, _ rhs: String, n: Int) -> (similarity: Double, intersectionCount: Int, unionCount: Int) {
        let left = ngramSet(lhs, n: n)
        let right = ngramSet(rhs, n: n)
        guard !left.isEmpty, !right.isEmpty else {
            let equalityScore = lhs == rhs ? 1.0 : 0.0
            return (equalityScore, lhs == rhs ? 1 : 0, lhs == rhs ? 1 : max(left.count, right.count))
        }

        let intersectionCount = left.intersection(right).count
        let unionCount = left.union(right).count
        guard unionCount > 0 else { return (0, 0, 0) }
        let similarity = Double(intersectionCount) / Double(unionCount)
        return (similarity, intersectionCount, unionCount)
    }

    private static func ngramSet(_ text: String, n: Int) -> Set<String> {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return [] }

        let size = max(1, n)
        if scalars.count < size {
            return [String(String.UnicodeScalarView(scalars))]
        }

        var grams: Set<String> = []
        grams.reserveCapacity(scalars.count - size + 1)

        for start in 0...(scalars.count - size) {
            let slice = scalars[start..<(start + size)]
            grams.insert(String(String.UnicodeScalarView(slice)))
        }

        return grams
    }

    private static func normalizedLevenshteinSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshteinDistance(lhs, rhs)
        return normalizedSimilarity(distance: distance, maxLength: max(lhs.count, rhs.count))
    }

    private static func normalizedSimilarity(distance: Int, maxLength: Int) -> Double {
        guard maxLength > 0 else { return 1 }
        let normalizedDistance = Double(distance) / Double(maxLength)
        return max(0, 1 - normalizedDistance)
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.unicodeScalars)
        let right = Array(rhs.unicodeScalars)
        guard !left.isEmpty, !right.isEmpty else {
            return max(left.count, right.count)
        }

        if left == right {
            return 0
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                let insertion = current[j - 1] + 1
                let deletion = previous[j] + 1
                current[j] = min(substitution, insertion, deletion)
            }
            swap(&previous, &current)
        }

        return previous[right.count]
    }

    private static func keyboardProximitySimilarity(_ lhs: String, _ rhs: String) -> Double {
        keyboardProximityStats(lhs, rhs).similarity
    }

    private static func keyboardProximityStats(_ lhs: String, _ rhs: String) -> (distance: Double, similarity: Double) {
        let left = qwertyComparableScalars(lhs)
        let right = qwertyComparableScalars(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            let distance = Double(max(lhs.count, rhs.count))
            return (distance, lhs == rhs ? 1 : 0)
        }

        if left == right {
            return (0, 1)
        }

        let insertionDeletionCost = 1.0
        var previous = Array(repeating: 0.0, count: right.count + 1)
        var current = Array(repeating: 0.0, count: right.count + 1)

        for j in 0...right.count {
            previous[j] = Double(j) * insertionDeletionCost
        }

        for i in 1...left.count {
            current[0] = Double(i) * insertionDeletionCost
            for j in 1...right.count {
                let substitution = previous[j - 1] + keyboardSubstitutionCost(left[i - 1], right[j - 1])
                let insertion = current[j - 1] + insertionDeletionCost
                let deletion = previous[j] + insertionDeletionCost
                current[j] = min(substitution, insertion, deletion)
            }
            swap(&previous, &current)
        }

        let maxLength = max(left.count, right.count)
        let distance = previous[right.count]
        let normalizedDistance = distance / Double(maxLength)
        return (distance, max(0, 1 - normalizedDistance))
    }

    private static func qwertyComparableScalars(_ text: String) -> [UnicodeScalar] {
        let qwerty = Hangul.convertHangulToQwerty(text).lowercased()
        return qwerty.unicodeScalars.filter { qwertyPositions[$0] != nil }
    }

    private static func keyboardSubstitutionCost(_ lhs: UnicodeScalar, _ rhs: UnicodeScalar) -> Double {
        if lhs == rhs {
            return 0
        }

        guard let left = qwertyPositions[lhs], let right = qwertyPositions[rhs] else {
            return 1
        }

        let distance = abs(left.x - right.x) + abs(left.y - right.y)
        if distance <= 1 {
            return 0.35
        }
        if distance <= 2 {
            return 0.65
        }
        return 1
    }

    private struct KeyPoint {
        let x: Double
        let y: Double
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let leftSet = Set(lhs.unicodeScalars)
        let rightSet = Set(rhs.unicodeScalars)
        guard !leftSet.isEmpty, !rightSet.isEmpty else { return 0 }

        let intersection = leftSet.intersection(rightSet).count
        let union = leftSet.union(rightSet).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static let qwertyPositions: [UnicodeScalar: KeyPoint] = {
        var result: [UnicodeScalar: KeyPoint] = [:]

        let rows: [(row: String, offset: Double)] = [
            ("1234567890", 0.0),
            ("qwertyuiop", 0.2),
            ("asdfghjkl", 0.6),
            ("zxcvbnm", 1.1),
        ]

        for (rowIndex, rowInfo) in rows.enumerated() {
            for (columnIndex, scalar) in rowInfo.row.unicodeScalars.enumerated() {
                result[scalar] = KeyPoint(x: Double(columnIndex) + rowInfo.offset, y: Double(rowIndex))
            }
        }

        return result
    }()
}
