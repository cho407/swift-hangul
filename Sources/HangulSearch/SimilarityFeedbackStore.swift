import Foundation
import CryptoKit

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
    public var storageRedaction: SimilarityFeedbackRedaction
    public var outputRedaction: SimilarityFeedbackRedaction
    public var redactionSalt: String

    public static let `default` = SimilarityFeedbackStoreOptions(
        maxEvents: 10_000,
        ttl: 60 * 60 * 24 * 30,
        storageRedaction: .none,
        outputRedaction: .hashQuery,
        redactionSalt: "swift-hangul-feedback"
    )

    public init(
        maxEvents: Int = 10_000,
        ttl: TimeInterval = 60 * 60 * 24 * 30,
        storageRedaction: SimilarityFeedbackRedaction = .none,
        outputRedaction: SimilarityFeedbackRedaction = .hashQuery,
        redactionSalt: String = "swift-hangul-feedback"
    ) {
        self.maxEvents = max(1, maxEvents)
        self.ttl = max(60, ttl)
        self.storageRedaction = storageRedaction
        self.outputRedaction = outputRedaction
        let normalizedSalt = redactionSalt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redactionSalt = normalizedSalt.isEmpty ? "swift-hangul-feedback" : normalizedSalt
    }
}

public enum SimilarityFeedbackRedaction: String, Codable, Sendable, Equatable {
    case none
    case hashQuery
    case hashQueryAndSelection
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
    private let redactionKey: SymmetricKey
    private var events: [SimilarityQueryEvent] = []
    private var droppedByTTL = 0
    private var droppedByCapacity = 0

    public init(options: SimilarityFeedbackStoreOptions = .default) {
        self.options = options
        self.redactionKey = SymmetricKey(data: Data(options.redactionSalt.utf8))
        self.events.reserveCapacity(min(options.maxEvents, 2_048))
    }

    public func record(_ event: SimilarityQueryEvent, now: Date = Date()) {
        events.append(applyRedaction(to: event, mode: options.storageRedaction))
        prune(now: now)
    }

    public func record(_ newEvents: [SimilarityQueryEvent], now: Date = Date()) {
        guard !newEvents.isEmpty else { return }
        events.append(contentsOf: newEvents.map { applyRedaction(to: $0, mode: options.storageRedaction) })
        prune(now: now)
    }

    public func snapshot(
        now: Date = Date(),
        redaction: SimilarityFeedbackRedaction? = nil
    ) -> [SimilarityQueryEvent] {
        prune(now: now)
        return redactedEvents(events, mode: redaction ?? options.outputRedaction)
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

    public func summary(
        now: Date = Date(),
        maxPairs: Int = 200,
        redaction: SimilarityFeedbackRedaction? = nil
    ) -> SimilarityFeedbackSummary {
        prune(now: now)
        let exportedEvents = redactedEvents(events, mode: redaction ?? options.outputRedaction)
        let topPairs = Self.buildPairStats(events: exportedEvents, maxPairs: maxPairs)
        let uniqueQueries = Set(exportedEvents.map(\.query)).count
        return SimilarityFeedbackSummary(
            generatedAt: now,
            totalEvents: exportedEvents.count,
            uniqueQueries: uniqueQueries,
            droppedByTTL: droppedByTTL,
            droppedByCapacity: droppedByCapacity,
            topPairs: topPairs
        )
    }

    public func summaryJSON(
        now: Date = Date(),
        maxPairs: Int = 200,
        redaction: SimilarityFeedbackRedaction? = nil
    ) throws -> Data {
        let summary = summary(now: now, maxPairs: maxPairs, redaction: redaction)
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

    private func redactedEvents(
        _ source: [SimilarityQueryEvent],
        mode: SimilarityFeedbackRedaction
    ) -> [SimilarityQueryEvent] {
        guard mode != .none else { return source }
        return source.map { applyRedaction(to: $0, mode: mode) }
    }

    private func applyRedaction(
        to event: SimilarityQueryEvent,
        mode: SimilarityFeedbackRedaction
    ) -> SimilarityQueryEvent {
        switch mode {
        case .none:
            return event
        case .hashQuery:
            return SimilarityQueryEvent(
                query: pseudonymize(event.query),
                selectedKey: event.selectedKey,
                timestamp: event.timestamp,
                outcome: event.outcome,
                locale: event.locale
            )
        case .hashQueryAndSelection:
            return SimilarityQueryEvent(
                query: pseudonymize(event.query),
                selectedKey: event.selectedKey.map { pseudonymize($0) },
                timestamp: event.timestamp,
                outcome: event.outcome,
                locale: event.locale
            )
        }
    }

    private func pseudonymize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let message = Data(trimmed.utf8)
        let digest = HMAC<SHA256>.authenticationCode(for: message, using: redactionKey)
        return "h:" + Self.hexString(digest)
    }

    private static func hexString(_ digest: HMAC<SHA256>.MAC) -> String {
        let hexDigits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)

        for byte in digest {
            bytes.append(hexDigits[Int(byte >> 4)])
            bytes.append(hexDigits[Int(byte & 0x0F)])
        }

        return String(decoding: bytes, as: UTF8.self)
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
