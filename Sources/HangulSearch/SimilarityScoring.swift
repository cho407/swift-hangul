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
    /// Effective result count is clamped to 1...10,000 at the search boundary.
    public var limit: Int
    public var ngramSize: Int
    /// Clamped to 1...100,000; retrieval retains at least limit * 10 candidates when available.
    public var candidateLimitPerVariant: Int
    public var includeLayoutVariants: Bool
    public var minimumScore: Double
    public var weights: SimilarityWeights
    /// Defaults to Levenshtein, including when decoding older option files.
    public var distanceAlgorithm: SimilarityDistanceAlgorithm

    public static let `default` = SimilarityOptions()

    public init(
        limit: Int = 20,
        ngramSize: Int = 2,
        candidateLimitPerVariant: Int = 1_200,
        includeLayoutVariants: Bool = true,
        minimumScore: Double = 0.2,
        weights: SimilarityWeights = .default,
        distanceAlgorithm: SimilarityDistanceAlgorithm = .levenshtein
    ) {
        self.limit = limit
        self.ngramSize = max(1, ngramSize)
        self.candidateLimitPerVariant = max(1, candidateLimitPerVariant)
        self.includeLayoutVariants = includeLayoutVariants
        self.minimumScore = min(1, max(0, minimumScore))
        self.weights = weights
        self.distanceAlgorithm = distanceAlgorithm
    }

    func validated() -> Self {
        var result = self
        result.limit = min(10_000, max(1, limit))
        result.ngramSize = min(3, max(1, ngramSize))
        result.candidateLimitPerVariant = min(100_000, max(1, candidateLimitPerVariant))
        result.minimumScore = minimumScore.isFinite ? min(1, max(0, minimumScore)) : 0.2
        result.weights = weights.sanitized()
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case limit, ngramSize, candidateLimitPerVariant, includeLayoutVariants, minimumScore, weights, distanceAlgorithm
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            limit: try values.decode(Int.self, forKey: .limit),
            ngramSize: try values.decode(Int.self, forKey: .ngramSize),
            candidateLimitPerVariant: try values.decode(Int.self, forKey: .candidateLimitPerVariant),
            includeLayoutVariants: try values.decode(Bool.self, forKey: .includeLayoutVariants),
            minimumScore: try values.decode(Double.self, forKey: .minimumScore),
            weights: try values.decode(SimilarityWeights.self, forKey: .weights),
            distanceAlgorithm: try values.decodeIfPresent(SimilarityDistanceAlgorithm.self, forKey: .distanceAlgorithm) ?? .levenshtein
        )
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

extension ScoredSearchResult: Sendable where Item: Sendable {}
extension ExplainedSearchResult: Sendable where Item: Sendable {}

enum SimilarityScorer {
    struct QueryFeatures: Sendable {
        let text: String
        let choseong: String
        let jamo: String
        let scalars: [UnicodeScalar]
        let jamoScalars: [UnicodeScalar]
        let keyboard: [UnicodeScalar]
        let grams: Set<String>
        let choseongOnly: Bool
    }

    static func queryVariants(for query: String, includeLayoutVariants: Bool) -> [String] {
        var seen: Set<String> = []
        var variants: [String] = []
        func append(_ text: String) {
            let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty, seen.insert(token).inserted { variants.append(token) }
        }
        append(query)
        if includeLayoutVariants {
            append(Hangul.convertQwertyToHangul(query))
            append(Hangul.convertHangulToQwerty(query))
        }
        return variants
    }

    static func prepareQuery(_ query: String, choseong: String, options: SimilarityOptions) -> QueryFeatures {
        let text = canonical(query)
        let onset = canonical(choseong)
        let onsetOnly = !text.isEmpty && text.unicodeScalars.allSatisfy {
            (0x3131...0x314E).contains($0.value) || (0x1100...0x1112).contains($0.value)
                || (0xFFA1...0xFFBE).contains($0.value)
        }
        let comparison = onsetOnly ? onset : text
        let jamo = onsetOnly ? onset : Hangul.disassemble(text)
        let scalars = Array(comparison.unicodeScalars)
        return QueryFeatures(text: text, choseong: onset, jamo: jamo, scalars: scalars,
                             jamoScalars: Array(jamo.unicodeScalars), keyboard: keyboardScalars(comparison),
                             grams: ngramSet(scalars, n: options.ngramSize), choseongOnly: onsetOnly)
    }

    static func score(
        query: QueryFeatures, target: String, targetChoseong: String,
        options: SimilarityOptions, cancellationCheck: (() throws -> Void)? = nil
    ) rethrows -> SimilarityScoreBreakdown {
        try calculate(query: query, target: target, targetChoseong: targetChoseong,
                      options: options, includeDetail: false, cancellationCheck: cancellationCheck).breakdown
    }

    static func score(
        query: String, target: String, queryChoseong: String, targetChoseong: String,
        options: SimilarityOptions
    ) -> SimilarityScoreBreakdown {
        score(query: prepareQuery(query, choseong: queryChoseong, options: options),
              target: target, targetChoseong: targetChoseong, options: options)
    }

    static func explain(
        query: String, target: String, queryChoseong: String, targetChoseong: String,
        options: SimilarityOptions, cancellationCheck: (() throws -> Void)? = nil
    ) rethrows -> (breakdown: SimilarityScoreBreakdown, detail: SimilarityExplanationDetail) {
        let result = try calculate(query: prepareQuery(query, choseong: queryChoseong, options: options),
                                   target: target, targetChoseong: targetChoseong, options: options,
                                   includeDetail: true, cancellationCheck: cancellationCheck)
        return (result.breakdown, result.detail!)
    }

    private static func calculate(
        query: QueryFeatures, target: String, targetChoseong: String,
        options: SimilarityOptions, includeDetail: Bool, cancellationCheck: (() throws -> Void)?
    ) rethrows -> (breakdown: SimilarityScoreBreakdown, detail: SimilarityExplanationDetail?) {
        try cancellationCheck?()
        let rhs = canonical(target)
        let onset = canonical(targetChoseong)
        let comparison = query.choseongOnly ? onset : rhs
        let targetScalars = Array(comparison.unicodeScalars)
        let targetJamo = query.choseongOnly ? onset : Hangul.disassemble(rhs)
        let jamoScalars = Array(targetJamo.unicodeScalars)
        let keyboard = keyboardScalars(comparison)
        let grams = ngramSet(targetScalars, n: options.ngramSize)
        let intersection = query.grams.intersection(grams).count
        let union = query.grams.count + grams.count - intersection
        let jaccard = union == 0 ? 0 : Double(intersection) / Double(union)
        let edit = try StringDistance.distance(query.scalars, targetScalars, algorithm: options.distanceAlgorithm,
                                               cancellationCheck: cancellationCheck)
        let jamoEdit = try StringDistance.distance(query.jamoScalars, jamoScalars, algorithm: options.distanceAlgorithm,
                                                   cancellationCheck: cancellationCheck)
        let keyboardDistance = try StringDistance.weightedDistance(query.keyboard, keyboard,
                                                                   substitutionCost: keyboardSubstitutionCost,
                                                                   cancellationCheck: cancellationCheck)
        let editSimilarity = similarity(Double(edit), max(query.scalars.count, targetScalars.count))
        let jamoSimilarity = similarity(Double(jamoEdit), max(query.jamoScalars.count, jamoScalars.count))
        let keyboardSimilarity = similarity(keyboardDistance, max(query.keyboard.count, keyboard.count))
        let weights = options.weights
        let sum = weights.editDistance + weights.jaccard + weights.keyboard + weights.jamo
        let core = ((editSimilarity * weights.editDistance) + (jaccard * weights.jaccard)
                    + (keyboardSimilarity * weights.keyboard) + (jamoSimilarity * weights.jamo)) / max(0.000_001, sum)
        let lhsComparison = query.choseongOnly ? query.choseong : query.text
        let exact = comparison == lhsComparison
        let exactBonus = exact ? weights.exactBonus : 0
        let prefixBonus = !exact && comparison.hasPrefix(lhsComparison) ? weights.prefixBonus : 0
        let total = query.scalars.isEmpty || targetScalars.isEmpty ? 0 : min(1, max(0, core + exactBonus + prefixBonus))
        let breakdown = SimilarityScoreBreakdown(
            editDistanceSimilarity: editSimilarity, jaccardSimilarity: jaccard,
            keyboardSimilarity: keyboardSimilarity, jamoSimilarity: jamoSimilarity,
            weightedCoreScore: core, prefixBonus: prefixBonus, exactBonus: exactBonus, totalScore: total
        )
        let detail: SimilarityExplanationDetail? = includeDetail ? .init(
            normalizedQuery: query.text, normalizedTarget: rhs, choseongQuery: query.choseong, choseongTarget: onset,
            jamoQuery: query.jamo, jamoTarget: targetJamo, editDistance: edit, jamoEditDistance: jamoEdit,
            keyboardDistance: keyboardDistance, jaccardIntersectionCount: intersection, jaccardUnionCount: union
        ) : nil
        return (breakdown, detail)
    }

    struct CoarseQuery {
        let scalars: Set<UnicodeScalar>
        let count: Int
        let first: UnicodeScalar?

        init(_ text: String) {
            scalars = Set(text.unicodeScalars)
            count = text.unicodeScalars.count
            first = text.unicodeScalars.first
        }

        func score(_ text: String) -> Double {
            let right = Set(text.unicodeScalars)
            guard !scalars.isEmpty, !right.isEmpty else { return 0 }
            let intersection = scalars.intersection(right).count
            guard intersection > 0 else { return 0 }
            let overlap = Double(intersection) / Double(scalars.count + right.count - intersection)
            let rightCount = text.unicodeScalars.count
            let length = 1 - Double(abs(count - rightCount)) / Double(max(count, rightCount))
            return min(1, overlap * 0.65 + length * 0.35 + (first == text.unicodeScalars.first ? 0.1 : 0))
        }
    }

    private static func canonical(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(normalized.unicodeScalars.filter { !$0.properties.isWhitespace }))
    }

    private static func ngramSet(_ scalars: [UnicodeScalar], n: Int) -> Set<String> {
        guard !scalars.isEmpty else { return [] }
        let size = min(scalars.count, max(1, n))
        var result: Set<String> = []
        result.reserveCapacity(scalars.count - size + 1)
        for i in 0...(scalars.count - size) {
            result.insert(String(String.UnicodeScalarView(scalars[i..<(i + size)])))
        }
        return result
    }

    private static func similarity(_ distance: Double, _ length: Int) -> Double {
        length == 0 ? 1 : max(0, 1 - distance / Double(length))
    }

    private static func keyboardScalars(_ text: String) -> [UnicodeScalar] {
        // Unknown keys remain literal characters instead of disappearing from the comparison.
        Array(Hangul.convertHangulToQwerty(text).lowercased().unicodeScalars)
    }

    private static func keyboardSubstitutionCost(_ lhs: UnicodeScalar, _ rhs: UnicodeScalar) -> Double {
        if lhs == rhs { return 0 }
        guard let left = qwertyPositions[lhs], let right = qwertyPositions[rhs] else { return 1 }
        let distance = abs(left.x - right.x) + abs(left.y - right.y)
        return distance <= 1 ? 0.35 : (distance <= 2 ? 0.65 : 1)
    }

    private struct KeyPoint: Sendable {
        let x: Double
        let y: Double
    }

    private static let qwertyPositions: [UnicodeScalar: KeyPoint] = {
        var result: [UnicodeScalar: KeyPoint] = [:]
        for (rowIndex, row) in [("1234567890", 0.0), ("qwertyuiop", 0.2), ("asdfghjkl", 0.6), ("zxcvbnm", 1.1)].enumerated() {
            for (column, scalar) in row.0.unicodeScalars.enumerated() {
                result[scalar] = KeyPoint(x: Double(column) + row.1, y: Double(rowIndex))
            }
        }
        return result
    }()
}
