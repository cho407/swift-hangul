import Foundation

public enum SearchRuntimeEnvironment: String, Codable, Sendable, CaseIterable {
    case development
    case staging
    case production
}

public enum SimilarityABBucket: String, Codable, Sendable {
    case control
    case treatment
}

public struct SimilarityABPolicy: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var treatmentRatio: Double
    public var salt: String

    public static let disabled = SimilarityABPolicy(enabled: false, treatmentRatio: 0, salt: "swift-hangul")

    public init(enabled: Bool = false, treatmentRatio: Double = 0, salt: String = "swift-hangul") {
        self.enabled = enabled
        self.treatmentRatio = min(1, max(0, treatmentRatio))
        self.salt = salt
    }
}

public struct SimilarityEnvironmentConfig: Codable, Sendable, Equatable {
    public var controlWeights: SimilarityWeights
    public var treatmentWeights: SimilarityWeights?
    public var abPolicy: SimilarityABPolicy

    public init(
        controlWeights: SimilarityWeights = .default,
        treatmentWeights: SimilarityWeights? = nil,
        abPolicy: SimilarityABPolicy = .disabled
    ) {
        self.controlWeights = controlWeights
        self.treatmentWeights = treatmentWeights
        self.abPolicy = abPolicy
    }
}

public struct SimilarityDeploymentConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var modelVersion: String
    public var updatedAt: Date
    public var environments: [SearchRuntimeEnvironment: SimilarityEnvironmentConfig]

    public init(
        schemaVersion: Int = 1,
        modelVersion: String = "v1",
        updatedAt: Date = Date(),
        environments: [SearchRuntimeEnvironment: SimilarityEnvironmentConfig]
    ) {
        self.schemaVersion = schemaVersion
        self.modelVersion = modelVersion
        self.updatedAt = updatedAt
        self.environments = environments
    }

    public static let `default` = SimilarityDeploymentConfig(
        environments: [
            .development: SimilarityEnvironmentConfig(
                controlWeights: .default,
                treatmentWeights: .default,
                abPolicy: SimilarityABPolicy(enabled: true, treatmentRatio: 1.0, salt: "dev")
            ),
            .staging: SimilarityEnvironmentConfig(
                controlWeights: .default,
                treatmentWeights: .default,
                abPolicy: SimilarityABPolicy(enabled: true, treatmentRatio: 0.5, salt: "staging")
            ),
            .production: SimilarityEnvironmentConfig(
                controlWeights: .default,
                treatmentWeights: nil,
                abPolicy: .disabled
            ),
        ]
    )
}

public extension SimilarityWeights {
    func sanitized() -> SimilarityWeights {
        SimilarityWeights(
            editDistance: Self.clamp(editDistance, min: 0.01, max: 2.0),
            jaccard: Self.clamp(jaccard, min: 0.01, max: 2.0),
            keyboard: Self.clamp(keyboard, min: 0.01, max: 2.0),
            jamo: Self.clamp(jamo, min: 0.01, max: 2.0),
            prefixBonus: Self.clamp(prefixBonus, min: 0.0, max: 0.5),
            exactBonus: Self.clamp(exactBonus, min: 0.0, max: 0.5)
        )
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

public extension SimilarityEnvironmentConfig {
    func sanitized(default defaultValue: SimilarityEnvironmentConfig = .init()) -> SimilarityEnvironmentConfig {
        var environment = self
        environment.controlWeights = environment.controlWeights.sanitized()
        environment.treatmentWeights = environment.treatmentWeights?.sanitized()

        let normalizedSalt = environment.abPolicy.salt.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSalt.isEmpty {
            environment.abPolicy.salt = defaultValue.abPolicy.salt
        }
        environment.abPolicy.treatmentRatio = min(1, max(0, environment.abPolicy.treatmentRatio))

        if environment.treatmentWeights == nil {
            environment.abPolicy.enabled = false
            environment.abPolicy.treatmentRatio = 0
        } else if !environment.abPolicy.enabled {
            environment.abPolicy.treatmentRatio = 0
        }

        return environment
    }
}

public extension SimilarityDeploymentConfig {
    func sanitized(default defaultConfig: SimilarityDeploymentConfig = .default) -> SimilarityDeploymentConfig {
        var normalized = self

        if normalized.schemaVersion <= 0 {
            normalized.schemaVersion = defaultConfig.schemaVersion
        }
        if normalized.modelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.modelVersion = defaultConfig.modelVersion
        }
        if normalized.updatedAt.timeIntervalSince1970 <= 0 {
            normalized.updatedAt = defaultConfig.updatedAt
        }

        var mergedEnvironments = defaultConfig.environments
        for (runtimeEnvironment, rawConfig) in environments {
            let defaultEnvironment = defaultConfig.environments[runtimeEnvironment] ?? .init()
            mergedEnvironments[runtimeEnvironment] = rawConfig.sanitized(default: defaultEnvironment)
        }
        normalized.environments = mergedEnvironments

        return normalized
    }
}

public struct ResolvedSimilarityWeights: Sendable, Equatable {
    public let environment: SearchRuntimeEnvironment
    public let bucket: SimilarityABBucket
    public let weights: SimilarityWeights
    public let modelVersion: String
    public let updatedAt: Date

    public init(
        environment: SearchRuntimeEnvironment,
        bucket: SimilarityABBucket,
        weights: SimilarityWeights,
        modelVersion: String,
        updatedAt: Date
    ) {
        self.environment = environment
        self.bucket = bucket
        self.weights = weights
        self.modelVersion = modelVersion
        self.updatedAt = updatedAt
    }
}

public enum SimilarityDeploymentError: Error {
    case missingEnvironment(SearchRuntimeEnvironment)
    case missingFile(URL)
}

public enum SimilarityWeightsResolver {
    public static func resolve(
        config: SimilarityDeploymentConfig,
        environment: SearchRuntimeEnvironment,
        userIdentifier: String?,
        forcedBucket: SimilarityABBucket? = nil
    ) throws -> ResolvedSimilarityWeights {
        guard let envConfig = config.environments[environment] else {
            throw SimilarityDeploymentError.missingEnvironment(environment)
        }

        let bucket = bucketFor(
            environmentConfig: envConfig,
            userIdentifier: userIdentifier,
            forcedBucket: forcedBucket
        )

        let weights: SimilarityWeights
        switch bucket {
        case .control:
            weights = envConfig.controlWeights
        case .treatment:
            weights = envConfig.treatmentWeights ?? envConfig.controlWeights
        }

        return ResolvedSimilarityWeights(
            environment: environment,
            bucket: bucket,
            weights: weights,
            modelVersion: config.modelVersion,
            updatedAt: config.updatedAt
        )
    }

    public static func resolveOrDefault(
        config: SimilarityDeploymentConfig,
        environment: SearchRuntimeEnvironment,
        userIdentifier: String?,
        forcedBucket: SimilarityABBucket? = nil,
        defaultConfig: SimilarityDeploymentConfig = .default
    ) -> ResolvedSimilarityWeights {
        let normalized = config.sanitized(default: defaultConfig)
        if let resolved = try? resolve(
            config: normalized,
            environment: environment,
            userIdentifier: userIdentifier,
            forcedBucket: forcedBucket
        ) {
            return resolved
        }

        let fallbackEnvironment: SearchRuntimeEnvironment = normalized.environments[.production] == nil
            ? (normalized.environments.keys.first ?? .production)
            : .production

        if let fallback = try? resolve(
            config: normalized,
            environment: fallbackEnvironment,
            userIdentifier: userIdentifier,
            forcedBucket: forcedBucket
        ) {
            return fallback
        }

        return ResolvedSimilarityWeights(
            environment: fallbackEnvironment,
            bucket: .control,
            weights: .default,
            modelVersion: normalized.modelVersion,
            updatedAt: normalized.updatedAt
        )
    }

    public static func bucketFor(
        environmentConfig: SimilarityEnvironmentConfig,
        userIdentifier: String?,
        forcedBucket: SimilarityABBucket? = nil
    ) -> SimilarityABBucket {
        if let forcedBucket {
            if forcedBucket == .treatment, environmentConfig.treatmentWeights == nil {
                return .control
            }
            return forcedBucket
        }

        if !environmentConfig.abPolicy.enabled {
            return .control
        }
        guard environmentConfig.treatmentWeights != nil else {
            return .control
        }

        let ratio = min(1, max(0, environmentConfig.abPolicy.treatmentRatio))
        if ratio <= 0 { return .control }
        if ratio >= 1 { return .treatment }

        guard let userIdentifier, !userIdentifier.isEmpty else {
            return .control
        }

        let hashInput = environmentConfig.abPolicy.salt + "|" + userIdentifier
        let bucket = hashPercent(hashInput)
        return bucket < ratio ? .treatment : .control
    }

    private static func hashPercent(_ value: String) -> Double {
        let bytes = Array(value.utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return Double(hash % 10_000) / 10_000.0
    }
}

public final class SimilarityConfigFileStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ config: SimilarityDeploymentConfig) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> SimilarityDeploymentConfig {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SimilarityDeploymentError.missingFile(fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SimilarityDeploymentConfig.self, from: data)
    }

    public func loadSanitized(defaultConfig: SimilarityDeploymentConfig = .default) throws -> SimilarityDeploymentConfig {
        try load().sanitized(default: defaultConfig)
    }

    public func loadOrDefault(defaultConfig: SimilarityDeploymentConfig = .default) -> SimilarityDeploymentConfig {
        (try? loadSanitized(defaultConfig: defaultConfig)) ?? defaultConfig.sanitized(default: defaultConfig)
    }

    public func loadIfExists() throws -> SimilarityDeploymentConfig? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try loadSanitized()
    }
}
