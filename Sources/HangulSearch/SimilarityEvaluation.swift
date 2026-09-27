import Foundation

public struct SimilarityEvaluationCase: Sendable {
    public let query: String
    /// Empty means no result should be recommended for this query.
    public let relevantKeys: Set<String>

    public init(query: String, relevantKeys: Set<String>) {
        self.query = query
        self.relevantKeys = relevantKeys
    }
}

public struct SimilarityQualityMetrics: Sendable {
    public let positiveCount: Int
    public let negativeCount: Int
    public let recallAtK: Double
    public let precisionAtK: Double
    public let mrr: Double
    public let falsePositiveRate: Double
}

public extension HangulSearchIndex {
    func evaluateSimilarity(
        cases: [SimilarityEvaluationCase], options: SimilarityOptions = .default
    ) -> SimilarityQualityMetrics {
        var positives = 0, negatives = 0, falsePositives = 0
        var hits = 0, relevant = 0, returned = 0
        var reciprocalSum = 0.0
        for sample in cases {
            let results = searchSimilar(sample.query, options: options)
            let keys = Set(results.map(\.matchedKey))
            returned += keys.count
            if sample.relevantKeys.isEmpty {
                negatives += 1
                if !keys.isEmpty { falsePositives += 1 }
            } else {
                positives += 1
                relevant += sample.relevantKeys.count
                hits += keys.intersection(sample.relevantKeys).count
                if let rank = results.firstIndex(where: { sample.relevantKeys.contains($0.matchedKey) }) {
                    reciprocalSum += 1 / Double(rank + 1)
                }
            }
        }
        return SimilarityQualityMetrics(
            positiveCount: positives, negativeCount: negatives,
            recallAtK: relevant == 0 ? 0 : Double(hits) / Double(relevant),
            precisionAtK: returned == 0 ? 0 : Double(hits) / Double(returned),
            mrr: positives == 0 ? 0 : reciprocalSum / Double(positives),
            falsePositiveRate: negatives == 0 ? 0 : Double(falsePositives) / Double(negatives)
        )
    }
}

enum SimilarityDataset {
    static func queryIdentity(_ query: String) -> String {
        let normalized = query.precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(normalized.unicodeScalars.filter { !$0.properties.isWhitespace }))
    }

    static func split(_ samples: [SimilarityTrainingSample], seed: UInt64 = 0) -> (training: [SimilarityTrainingSample], validation: [SimilarityTrainingSample]) {
        // Stable sampling, independent of Swift's per-process randomized Hasher.
        func order(_ identity: String) -> UInt64 {
            identity.utf8.reduce(14_695_981_039_346_656_037 ^ seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let identities = Set(samples.map { queryIdentity($0.query) }).sorted {
            let left = order($0), right = order($1)
            return left == right ? $0 < $1 : left < right
        }
        guard identities.count > 1 else { return (samples, []) }
        let heldOut = Set(identities.prefix(max(1, identities.count / 5)))
        return (samples.filter { !heldOut.contains(queryIdentity($0.query)) },
                samples.filter { heldOut.contains(queryIdentity($0.query)) })
    }
}
