import Foundation

public struct SimilarityQueryEvent: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        case acceptedSuggestion
        case clickedResult
        case noSuggestion
        case unknown
    }

    public let query: String
    public let selectedKey: String?
    public let timestamp: Date
    public let outcome: Outcome
    public let locale: String?

    public init(
        query: String,
        selectedKey: String?,
        timestamp: Date = Date(),
        outcome: Outcome = .unknown,
        locale: String? = nil
    ) {
        self.query = query
        self.selectedKey = selectedKey
        self.timestamp = timestamp
        self.outcome = outcome
        self.locale = locale
    }
}

public struct SimilarityFeedbackStoreOptions: Sendable, Equatable {
    public var maxEvents: Int
    public var ttl: TimeInterval

    public static let `default` = SimilarityFeedbackStoreOptions(
        maxEvents: 10_000,
        ttl: 60 * 60 * 24 * 30
    )

    public init(maxEvents: Int = 10_000, ttl: TimeInterval = 60 * 60 * 24 * 30) {
        self.maxEvents = max(1, maxEvents)
        self.ttl = max(60, ttl)
    }
}

public struct SimilarityFeedbackPairStat: Codable, Sendable, Equatable {
    public let query: String
    public let selectedKey: String
    public let count: Int
    public let lastSeen: Date

    public init(query: String, selectedKey: String, count: Int, lastSeen: Date) {
        self.query = query
        self.selectedKey = selectedKey
        self.count = count
        self.lastSeen = lastSeen
    }
}

public struct SimilarityFeedbackSummary: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let totalEvents: Int
    public let uniqueQueries: Int
    public let droppedByTTL: Int
    public let droppedByCapacity: Int
    public let topPairs: [SimilarityFeedbackPairStat]

    public init(
        generatedAt: Date,
        totalEvents: Int,
        uniqueQueries: Int,
        droppedByTTL: Int,
        droppedByCapacity: Int,
        topPairs: [SimilarityFeedbackPairStat]
    ) {
        self.generatedAt = generatedAt
        self.totalEvents = totalEvents
        self.uniqueQueries = uniqueQueries
        self.droppedByTTL = droppedByTTL
        self.droppedByCapacity = droppedByCapacity
        self.topPairs = topPairs
    }
}

public actor SimilarityFeedbackStore {
    private let options: SimilarityFeedbackStoreOptions
    private var events: [SimilarityQueryEvent] = []
    private var droppedByTTL = 0
    private var droppedByCapacity = 0

    public init(options: SimilarityFeedbackStoreOptions = .default) {
        self.options = options
        self.events.reserveCapacity(min(options.maxEvents, 2_048))
    }

    public func record(_ event: SimilarityQueryEvent, now: Date = Date()) {
        events.append(event)
        prune(now: now)
    }

    public func record(_ newEvents: [SimilarityQueryEvent], now: Date = Date()) {
        guard !newEvents.isEmpty else { return }
        events.append(contentsOf: newEvents)
        prune(now: now)
    }

    public func snapshot(now: Date = Date()) -> [SimilarityQueryEvent] {
        prune(now: now)
        return events
    }

    public func trainingSamples(
        now: Date = Date(),
        maxSamples: Int = 5_000,
        minOccurrences: Int = 1
    ) -> [SimilarityTrainingSample] {
        prune(now: now)
        return Self.trainingSamples(
            from: events,
            maxSamples: maxSamples,
            minOccurrences: minOccurrences
        )
    }

    public func summary(now: Date = Date(), maxPairs: Int = 200) -> SimilarityFeedbackSummary {
        prune(now: now)
        let topPairs = Self.buildPairStats(events: events, maxPairs: maxPairs)
        let uniqueQueries = Set(events.map(\.query)).count
        return SimilarityFeedbackSummary(
            generatedAt: now,
            totalEvents: events.count,
            uniqueQueries: uniqueQueries,
            droppedByTTL: droppedByTTL,
            droppedByCapacity: droppedByCapacity,
            topPairs: topPairs
        )
    }

    public func summaryJSON(now: Date = Date(), maxPairs: Int = 200) throws -> Data {
        let summary = summary(now: now, maxPairs: maxPairs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(summary)
    }

    public static func trainingSamples(
        from events: [SimilarityQueryEvent],
        maxSamples: Int = 5_000,
        minOccurrences: Int = 1
    ) -> [SimilarityTrainingSample] {
        let pairStats = buildPairStats(events: events, maxPairs: maxSamples * 2)
        guard !pairStats.isEmpty else { return [] }

        let threshold = max(1, minOccurrences)
        var samples: [SimilarityTrainingSample] = []
        samples.reserveCapacity(min(maxSamples, pairStats.count))

        for stat in pairStats where stat.count >= threshold {
            samples.append(
                SimilarityTrainingSample(query: stat.query, expectedKey: stat.selectedKey)
            )
            if samples.count >= maxSamples {
                break
            }
        }

        return samples
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-options.ttl)
        let beforeTTL = events.count
        events.removeAll { $0.timestamp < cutoff }
        droppedByTTL += max(0, beforeTTL - events.count)

        if events.count > options.maxEvents {
            let overflow = events.count - options.maxEvents
            events.removeFirst(overflow)
            droppedByCapacity += overflow
        }
    }

    private static func buildPairStats(events: [SimilarityQueryEvent], maxPairs: Int) -> [SimilarityFeedbackPairStat] {
        guard !events.isEmpty else { return [] }

        struct PairKey: Hashable {
            let query: String
            let selectedKey: String
        }

        var counter: [PairKey: (count: Int, lastSeen: Date)] = [:]
        counter.reserveCapacity(min(events.count, 4_096))

        for event in events {
            let normalizedQuery = event.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty,
                  let selected = event.selectedKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !selected.isEmpty else {
                continue
            }

            let key = PairKey(query: normalizedQuery, selectedKey: selected)
            if let existing = counter[key] {
                counter[key] = (
                    count: existing.count + 1,
                    lastSeen: max(existing.lastSeen, event.timestamp)
                )
            } else {
                counter[key] = (count: 1, lastSeen: event.timestamp)
            }
        }

        let sorted = counter
            .map { item in
                SimilarityFeedbackPairStat(
                    query: item.key.query,
                    selectedKey: item.key.selectedKey,
                    count: item.value.count,
                    lastSeen: item.value.lastSeen
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.lastSeen > rhs.lastSeen
                }
                return lhs.count > rhs.count
            }

        return Array(sorted.prefix(max(1, maxPairs)))
    }
}
