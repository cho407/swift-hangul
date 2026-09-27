import Foundation

public struct SimilarityTrainingSample: Sendable {
    public let query: String
    public let expectedKey: String

    public init(query: String, expectedKey: String) {
        self.query = query
        self.expectedKey = expectedKey
    }
}

public struct SimilarityEvaluationOptions: Sendable {
    public var limit: Int
    public var ngramSize: Int
    public var candidateLimitPerVariant: Int
    public var includeLayoutVariants: Bool
    public var minimumScore: Double
    public var weights: SimilarityWeights
    public var distanceAlgorithm: SimilarityDistanceAlgorithm

    public static let `default` = SimilarityEvaluationOptions()

    public init(
        limit: Int = 5,
        ngramSize: Int = 2,
        candidateLimitPerVariant: Int = 300,
        includeLayoutVariants: Bool = true,
        minimumScore: Double = 0.0,
        weights: SimilarityWeights = .default,
        distanceAlgorithm: SimilarityDistanceAlgorithm = .levenshtein
    ) {
        self.limit = max(1, limit)
        self.ngramSize = max(1, ngramSize)
        self.candidateLimitPerVariant = max(1, candidateLimitPerVariant)
        self.includeLayoutVariants = includeLayoutVariants
        self.minimumScore = min(1, max(0, minimumScore))
        self.weights = weights
        self.distanceAlgorithm = distanceAlgorithm
    }
}

public struct SimilarityEvaluationMetrics: Sendable {
    public let sampleCount: Int
    public let top1: Double
    public let top3: Double
    public let mrr: Double
    public let hitRate: Double

    public init(sampleCount: Int, top1: Double, top3: Double, mrr: Double, hitRate: Double) {
        self.sampleCount = sampleCount
        self.top1 = top1
        self.top3 = top3
        self.mrr = mrr
        self.hitRate = hitRate
    }

    public var objectiveScore: Double {
        (mrr * 0.5) + (top1 * 0.35) + (top3 * 0.15)
    }
}

public struct SimilarityTuningOptions: Sendable {
    public var baseWeights: SimilarityWeights
    public var limit: Int
    public var ngramSize: Int
    public var candidateLimitPerVariant: Int
    public var includeLayoutVariants: Bool
    public var minimumScore: Double
    public var maxCandidates: Int
    public var leaderboardSize: Int
    public var seed: UInt64
    public var distanceAlgorithm: SimilarityDistanceAlgorithm

    public static let `default` = SimilarityTuningOptions()

    public init(
        baseWeights: SimilarityWeights = .default,
        limit: Int = 5,
        ngramSize: Int = 2,
        candidateLimitPerVariant: Int = 300,
        includeLayoutVariants: Bool = true,
        minimumScore: Double = 0.0,
        maxCandidates: Int = 80,
        leaderboardSize: Int = 10,
        seed: UInt64 = 0xD0C0_2026_0219_0001,
        distanceAlgorithm: SimilarityDistanceAlgorithm = .levenshtein
    ) {
        self.baseWeights = baseWeights
        self.limit = max(1, limit)
        self.ngramSize = max(1, ngramSize)
        self.candidateLimitPerVariant = max(1, candidateLimitPerVariant)
        self.includeLayoutVariants = includeLayoutVariants
        self.minimumScore = min(1, max(0, minimumScore))
        self.maxCandidates = max(1, maxCandidates)
        self.leaderboardSize = max(1, leaderboardSize)
        self.seed = seed
        self.distanceAlgorithm = distanceAlgorithm
    }
}

public struct SimilarityTuningCandidate: Sendable {
    public let weights: SimilarityWeights
    public let metrics: SimilarityEvaluationMetrics
    public let objectiveScore: Double

    public init(weights: SimilarityWeights, metrics: SimilarityEvaluationMetrics) {
        self.weights = weights
        self.metrics = metrics
        self.objectiveScore = metrics.objectiveScore
    }
}

public struct SimilarityTuningReport: Sendable {
    public let bestWeights: SimilarityWeights
    public let baselineMetrics: SimilarityEvaluationMetrics
    public let bestMetrics: SimilarityEvaluationMetrics
    public let evaluatedCandidates: Int
    public let leaderboard: [SimilarityTuningCandidate]
    public let validationBaselineMetrics: SimilarityEvaluationMetrics?
    public let validationBestMetrics: SimilarityEvaluationMetrics?
    public let usedValidationFallback: Bool

    public init(
        bestWeights: SimilarityWeights,
        baselineMetrics: SimilarityEvaluationMetrics,
        bestMetrics: SimilarityEvaluationMetrics,
        evaluatedCandidates: Int,
        leaderboard: [SimilarityTuningCandidate],
        validationBaselineMetrics: SimilarityEvaluationMetrics? = nil,
        validationBestMetrics: SimilarityEvaluationMetrics? = nil,
        usedValidationFallback: Bool = false
    ) {
        self.bestWeights = bestWeights
        self.baselineMetrics = baselineMetrics
        self.bestMetrics = bestMetrics
        self.evaluatedCandidates = evaluatedCandidates
        self.leaderboard = leaderboard
        self.validationBaselineMetrics = validationBaselineMetrics
        self.validationBestMetrics = validationBestMetrics
        self.usedValidationFallback = usedValidationFallback
    }
}

public extension HangulSearchIndex {
    func evaluateSimilarity(
        samples: [SimilarityTrainingSample],
        options: SimilarityEvaluationOptions = .default
    ) -> SimilarityEvaluationMetrics {
        guard !samples.isEmpty else {
            return SimilarityEvaluationMetrics(sampleCount: 0, top1: 0, top3: 0, mrr: 0, hitRate: 0)
        }

        var top1Hits = 0
        var top3Hits = 0
        var hitHits = 0
        var reciprocalSum = 0.0

        let searchOptions = SimilarityOptions(
            limit: options.limit,
            ngramSize: options.ngramSize,
            candidateLimitPerVariant: options.candidateLimitPerVariant,
            includeLayoutVariants: options.includeLayoutVariants,
            minimumScore: options.minimumScore,
            weights: options.weights,
            distanceAlgorithm: options.distanceAlgorithm
        ).validated()

        for sample in samples {
            let ranked = searchSimilar(sample.query, options: searchOptions)
            if let rank = ranked.firstIndex(where: { $0.matchedKey == sample.expectedKey }) {
                if rank == 0 {
                    top1Hits += 1
                }
                if rank < 3 {
                    top3Hits += 1
                }
                if rank < searchOptions.limit {
                    hitHits += 1
                }
                reciprocalSum += 1.0 / Double(rank + 1)
            }
        }

        let count = Double(samples.count)
        return SimilarityEvaluationMetrics(
            sampleCount: samples.count,
            top1: Double(top1Hits) / count,
            top3: Double(top3Hits) / count,
            mrr: reciprocalSum / count,
            hitRate: Double(hitHits) / count
        )
    }

    func tuneSimilarityWeights(
        samples: [SimilarityTrainingSample],
        options: SimilarityTuningOptions = .default
    ) -> SimilarityTuningReport {
        tuneSimilarityWeights(samples: samples, validationSamples: [], options: options)
    }

    func tuneSimilarityWeights(
        samples: [SimilarityTrainingSample],
        validationSamples: [SimilarityTrainingSample],
        options: SimilarityTuningOptions = .default
    ) -> SimilarityTuningReport {
        var options = options
        options.baseWeights = options.baseWeights.sanitized()
        options.maxCandidates = min(1_024, max(1, options.maxCandidates))
        options.leaderboardSize = min(options.maxCandidates, max(1, options.leaderboardSize))
        let heldOut = Set(validationSamples.map { SimilarityDataset.queryIdentity($0.query) })
        let samples = samples.filter { !heldOut.contains(SimilarityDataset.queryIdentity($0.query)) }
        let baselineEvalOptions = SimilarityEvaluationOptions(
            limit: options.limit,
            ngramSize: options.ngramSize,
            candidateLimitPerVariant: options.candidateLimitPerVariant,
            includeLayoutVariants: options.includeLayoutVariants,
            minimumScore: options.minimumScore,
            weights: options.baseWeights,
            distanceAlgorithm: options.distanceAlgorithm
        )
        let baseline = evaluateSimilarity(samples: samples, options: baselineEvalOptions)

        let weightCandidates = Self.generateWeightCandidates(
            base: options.baseWeights,
            maxCandidates: options.maxCandidates,
            seed: options.seed
        )

        var evaluated: [SimilarityTuningCandidate] = []
        evaluated.reserveCapacity(weightCandidates.count)

        for weights in weightCandidates {
            let evalOptions = SimilarityEvaluationOptions(
                limit: options.limit,
                ngramSize: options.ngramSize,
                candidateLimitPerVariant: options.candidateLimitPerVariant,
                includeLayoutVariants: options.includeLayoutVariants,
                minimumScore: options.minimumScore,
                weights: weights,
                distanceAlgorithm: options.distanceAlgorithm
            )
            let metrics = evaluateSimilarity(samples: samples, options: evalOptions)
            evaluated.append(SimilarityTuningCandidate(weights: weights, metrics: metrics))
        }

        let sorted = evaluated.sorted(by: Self.isBetterCandidate(_:_:))
        var best = sorted.first ?? SimilarityTuningCandidate(weights: options.baseWeights, metrics: baseline)
        let leaderboard = Array(sorted.prefix(options.leaderboardSize))
        var validationBaseline: SimilarityEvaluationMetrics?
        var validationBest: SimilarityEvaluationMetrics?
        var usedFallback = false
        if !validationSamples.isEmpty {
            let control = evaluateSimilarity(samples: validationSamples, options: baselineEvalOptions)
            var validationOptions = baselineEvalOptions
            validationOptions.weights = best.weights
            let treatment = evaluateSimilarity(samples: validationSamples, options: validationOptions)
            validationBaseline = control
            validationBest = treatment
            if samples.isEmpty || treatment.objectiveScore < control.objectiveScore {
                best = .init(weights: options.baseWeights, metrics: baseline)
                validationBest = control
                usedFallback = true
            }
        }

        return SimilarityTuningReport(
            bestWeights: best.weights,
            baselineMetrics: baseline,
            bestMetrics: best.metrics,
            evaluatedCandidates: evaluated.count,
            leaderboard: leaderboard,
            validationBaselineMetrics: validationBaseline,
            validationBestMetrics: validationBest,
            usedValidationFallback: usedFallback
        )
    }

    private static func isBetterCandidate(_ lhs: SimilarityTuningCandidate, _ rhs: SimilarityTuningCandidate) -> Bool {
        if lhs.objectiveScore == rhs.objectiveScore {
            if lhs.metrics.mrr == rhs.metrics.mrr {
                if lhs.metrics.top1 == rhs.metrics.top1 {
                    return lhs.metrics.top3 > rhs.metrics.top3
                }
                return lhs.metrics.top1 > rhs.metrics.top1
            }
            return lhs.metrics.mrr > rhs.metrics.mrr
        }
        return lhs.objectiveScore > rhs.objectiveScore
    }

    private static func generateWeightCandidates(
        base: SimilarityWeights,
        maxCandidates: Int,
        seed: UInt64
    ) -> [SimilarityWeights] {
        var candidates: [SimilarityWeights] = []
        candidates.reserveCapacity(maxCandidates)
        var fingerprints: Set<String> = []
        fingerprints.reserveCapacity(maxCandidates * 2)

        func addCandidate(_ weights: SimilarityWeights) {
            guard candidates.count < maxCandidates else { return }
            let normalized = normalizedWeights(weights)
            let key = fingerprint(normalized)
            if fingerprints.insert(key).inserted {
                candidates.append(normalized)
            }
        }

        addCandidate(base)

        let coreFactors: [Double] = [0.65, 0.8, 1.0, 1.2, 1.35]
        for factor in coreFactors {
            addCandidate(base.scaled(edit: factor))
            addCandidate(base.scaled(jaccard: factor))
            addCandidate(base.scaled(keyboard: factor))
            addCandidate(base.scaled(jamo: factor))
            addCandidate(base.scaledCore(factor))
        }

        let bonusFactors: [Double] = [0.5, 0.8, 1.0, 1.2, 1.5]
        for factor in bonusFactors {
            addCandidate(base.scaledBonuses(factor))
        }

        var rng = DeterministicRNG(state: seed)
        var attempts = 0
        while candidates.count < maxCandidates && attempts < maxCandidates * 20 {
            attempts += 1
            var candidate = base
            candidate.editDistance *= rng.uniform(in: 0.5...1.5)
            candidate.jaccard *= rng.uniform(in: 0.5...1.5)
            candidate.keyboard *= rng.uniform(in: 0.5...1.5)
            candidate.jamo *= rng.uniform(in: 0.5...1.5)
            candidate.prefixBonus *= rng.uniform(in: 0.2...2.0)
            candidate.exactBonus *= rng.uniform(in: 0.2...2.0)
            addCandidate(candidate)
        }

        return candidates
    }

    private static func normalizedWeights(_ weights: SimilarityWeights) -> SimilarityWeights {
        weights.sanitized()
    }

    private static func fingerprint(_ weights: SimilarityWeights) -> String {
        String(
            format: "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
            weights.editDistance,
            weights.jaccard,
            weights.keyboard,
            weights.jamo,
            weights.prefixBonus,
            weights.exactBonus
        )
    }

}

private extension SimilarityWeights {
    func scaled(edit factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance * factor,
            jaccard: jaccard,
            keyboard: keyboard,
            jamo: jamo,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus
        )
    }

    func scaled(jaccard factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance,
            jaccard: jaccard * factor,
            keyboard: keyboard,
            jamo: jamo,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus
        )
    }

    func scaled(keyboard factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance,
            jaccard: jaccard,
            keyboard: keyboard * factor,
            jamo: jamo,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus
        )
    }

    func scaled(jamo factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance,
            jaccard: jaccard,
            keyboard: keyboard,
            jamo: jamo * factor,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus
        )
    }

    func scaledCore(_ factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance * factor,
            jaccard: jaccard * factor,
            keyboard: keyboard * factor,
            jamo: jamo * factor,
            prefixBonus: prefixBonus,
            exactBonus: exactBonus
        )
    }

    func scaledBonuses(_ factor: Double) -> SimilarityWeights {
        SimilarityWeights(
            editDistance: editDistance,
            jaccard: jaccard,
            keyboard: keyboard,
            jamo: jamo,
            prefixBonus: prefixBonus * factor,
            exactBonus: exactBonus * factor
        )
    }
}

private struct DeterministicRNG {
    private(set) var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func uniform(in range: ClosedRange<Double>) -> Double {
        let raw = next()
        let unit = Double(raw >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
