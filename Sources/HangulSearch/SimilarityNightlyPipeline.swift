import Foundation

public struct SimilarityNightlyTuningOptions: Sendable, Equatable {
    public var environment: SearchRuntimeEnvironment
    public var targetBucket: SimilarityABBucket
    public var minOccurrences: Int
    public var maxSamples: Int
    public var evaluationLimit: Int
    public var ngramSize: Int
    public var candidateLimitPerVariant: Int
    public var includeLayoutVariants: Bool
    public var minimumScore: Double
    public var maxCandidates: Int
    public var leaderboardSize: Int
    public var seed: UInt64
    public var modelVersionPrefix: String

    public static let `default` = SimilarityNightlyTuningOptions()

    public init(
        environment: SearchRuntimeEnvironment = .staging,
        targetBucket: SimilarityABBucket = .treatment,
        minOccurrences: Int = 2,
        maxSamples: Int = 5_000,
        evaluationLimit: Int = 5,
        ngramSize: Int = 2,
        candidateLimitPerVariant: Int = 300,
        includeLayoutVariants: Bool = true,
        minimumScore: Double = 0.0,
        maxCandidates: Int = 80,
        leaderboardSize: Int = 10,
        seed: UInt64 = 0xA192_2026_0225_0001,
        modelVersionPrefix: String = "nightly"
    ) {
        self.environment = environment
        self.targetBucket = targetBucket
        self.minOccurrences = max(1, minOccurrences)
        self.maxSamples = max(1, maxSamples)
        self.evaluationLimit = max(1, evaluationLimit)
        self.ngramSize = max(1, ngramSize)
        self.candidateLimitPerVariant = max(1, candidateLimitPerVariant)
        self.includeLayoutVariants = includeLayoutVariants
        self.minimumScore = min(1, max(0, minimumScore))
        self.maxCandidates = max(1, maxCandidates)
        self.leaderboardSize = max(1, leaderboardSize)
        self.seed = seed
        self.modelVersionPrefix = modelVersionPrefix
    }
}

public struct SimilarityNightlyTuningResult: Sendable {
    public let sampleCount: Int
    public let baselineMetrics: SimilarityEvaluationMetrics
    public let bestMetrics: SimilarityEvaluationMetrics
    public let bestWeights: SimilarityWeights
    public let tuningReport: SimilarityTuningReport
    public let updatedConfig: SimilarityDeploymentConfig

    public init(
        sampleCount: Int,
        baselineMetrics: SimilarityEvaluationMetrics,
        bestMetrics: SimilarityEvaluationMetrics,
        bestWeights: SimilarityWeights,
        tuningReport: SimilarityTuningReport,
        updatedConfig: SimilarityDeploymentConfig
    ) {
        self.sampleCount = sampleCount
        self.baselineMetrics = baselineMetrics
        self.bestMetrics = bestMetrics
        self.bestWeights = bestWeights
        self.tuningReport = tuningReport
        self.updatedConfig = updatedConfig
    }
}

public enum SimilarityNightlyTuningError: Error {
    case missingEnvironment(SearchRuntimeEnvironment)
    case insufficientSamples
}

public extension HangulSearchIndex {
    func runNightlyTuning(
        feedbackEvents: [SimilarityQueryEvent],
        deploymentConfig: SimilarityDeploymentConfig,
        options: SimilarityNightlyTuningOptions = .default,
        now: Date = Date()
    ) throws -> SimilarityNightlyTuningResult {
        let normalizedConfig = deploymentConfig.sanitized()
        guard var environmentConfig = normalizedConfig.environments[options.environment] else {
            throw SimilarityNightlyTuningError.missingEnvironment(options.environment)
        }

        let samples = SimilarityFeedbackStore.trainingSamples(
            from: feedbackEvents,
            maxSamples: options.maxSamples,
            minOccurrences: options.minOccurrences
        )
        guard !samples.isEmpty else {
            throw SimilarityNightlyTuningError.insufficientSamples
        }

        let baseWeights: SimilarityWeights = {
            switch options.targetBucket {
            case .control:
                return environmentConfig.controlWeights
            case .treatment:
                return environmentConfig.treatmentWeights ?? environmentConfig.controlWeights
            }
        }()

        let tuningOptions = SimilarityTuningOptions(
            baseWeights: baseWeights,
            limit: options.evaluationLimit,
            ngramSize: options.ngramSize,
            candidateLimitPerVariant: options.candidateLimitPerVariant,
            includeLayoutVariants: options.includeLayoutVariants,
            minimumScore: options.minimumScore,
            maxCandidates: options.maxCandidates,
            leaderboardSize: options.leaderboardSize,
            seed: options.seed
        )

        let report = tuneSimilarityWeights(samples: samples, options: tuningOptions)

        switch options.targetBucket {
        case .control:
            environmentConfig.controlWeights = report.bestWeights
        case .treatment:
            environmentConfig.treatmentWeights = report.bestWeights
            if !environmentConfig.abPolicy.enabled {
                environmentConfig.abPolicy.enabled = true
                environmentConfig.abPolicy.treatmentRatio = max(0.05, environmentConfig.abPolicy.treatmentRatio)
            }
        }

        var updated = normalizedConfig
        updated.environments[options.environment] = environmentConfig
        updated.updatedAt = now
        updated.modelVersion = Self.nextModelVersion(
            previous: normalizedConfig.modelVersion,
            prefix: options.modelVersionPrefix,
            environment: options.environment,
            date: now
        )

        return SimilarityNightlyTuningResult(
            sampleCount: samples.count,
            baselineMetrics: report.baselineMetrics,
            bestMetrics: report.bestMetrics,
            bestWeights: report.bestWeights,
            tuningReport: report,
            updatedConfig: updated
        )
    }

    private static func nextModelVersion(
        previous: String,
        prefix: String,
        environment: SearchRuntimeEnvironment,
        date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        return "\(prefix)-\(environment.rawValue)-\(stamp)-from-\(previous)"
    }
}
