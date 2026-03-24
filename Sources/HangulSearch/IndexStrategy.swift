import Foundation
import HangulCore

public enum IndexStrategy: Sendable {
    case precompute
    case lazyCache
    case ngram(k: Int)
}

public enum CachePolicy: Sendable {
    case none
    case lru(capacity: Int)
}

public enum LazyWarmupPolicy: Sendable {
    case none
    case background
}

public struct SearchPolicy: Sendable {
    public var choseongOptions: ChoseongOptions
    public var indexStrategy: IndexStrategy
    public var cache: CachePolicy
    public var lazyWarmup: LazyWarmupPolicy
    public var maxQueryLength: Int?
    public var maxCandidateScan: Int?
    public var maxCachedResultCount: Int?

    public static let `default` = SearchPolicy(
        choseongOptions: .default,
        indexStrategy: .precompute,
        cache: .none,
        lazyWarmup: .none,
        maxQueryLength: 256,
        maxCandidateScan: nil,
        maxCachedResultCount: 1_024
    )

    public init(
        choseongOptions: ChoseongOptions = .default,
        indexStrategy: IndexStrategy = .precompute,
        cache: CachePolicy = .none,
        lazyWarmup: LazyWarmupPolicy = .none,
        maxQueryLength: Int? = 256,
        maxCandidateScan: Int? = nil,
        maxCachedResultCount: Int? = 1_024
    ) {
        self.choseongOptions = choseongOptions
        self.indexStrategy = indexStrategy
        self.cache = cache
        self.lazyWarmup = lazyWarmup
        if let maxQueryLength {
            self.maxQueryLength = max(1, maxQueryLength)
        } else {
            self.maxQueryLength = nil
        }
        if let maxCandidateScan {
            self.maxCandidateScan = max(1, maxCandidateScan)
        } else {
            self.maxCandidateScan = nil
        }
        if let maxCachedResultCount {
            self.maxCachedResultCount = max(1, maxCachedResultCount)
        } else {
            self.maxCachedResultCount = nil
        }
    }
}

public enum MatchMode: String, Sendable {
    case contains
    case prefix
    case exact

    @inlinable
    func matches(text: String, query: String) -> Bool {
        switch self {
        case .contains:
            return text.contains(query)
        case .prefix:
            return text.hasPrefix(query)
        case .exact:
            return Self.matchesExact(text: text, query: query)
        }
    }

    @inlinable
    static func matchesExact(text: String, query: String) -> Bool {
        if text == query { return true }
        if query.isEmpty { return false }

        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if token == query {
                return true
            }
        }
        return false
    }
}
