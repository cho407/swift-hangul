import Foundation
import Combine
import HangulSearch

public struct HangulSearchUIOptions: Sendable, Equatable {
    public var mode: MatchMode
    public var debounceMilliseconds: Int
    public var minimumQueryLength: Int
    public var trimWhitespace: Bool
    public var clearResultsWhenQueryEmpty: Bool
    public var maxResults: Int?
    public var fallbackToSimilarityWhenNoMatch: Bool
    public var similarityOptions: SimilarityOptions

    public static let `default` = HangulSearchUIOptions()

    public init(
        mode: MatchMode = .contains,
        debounceMilliseconds: Int = 220,
        minimumQueryLength: Int = 1,
        trimWhitespace: Bool = true,
        clearResultsWhenQueryEmpty: Bool = true,
        maxResults: Int? = 50,
        fallbackToSimilarityWhenNoMatch: Bool = true,
        similarityOptions: SimilarityOptions = .default
    ) {
        self.mode = mode
        self.debounceMilliseconds = max(0, debounceMilliseconds)
        self.minimumQueryLength = max(1, minimumQueryLength)
        self.trimWhitespace = trimWhitespace
        self.clearResultsWhenQueryEmpty = clearResultsWhenQueryEmpty
        if let maxResults {
            self.maxResults = max(1, maxResults)
        } else {
            self.maxResults = nil
        }
        self.fallbackToSimilarityWhenNoMatch = fallbackToSimilarityWhenNoMatch
        self.similarityOptions = similarityOptions
    }
}

@MainActor
public final class HangulSearchController<Item>: ObservableObject {
    @Published public private(set) var query: String
    @Published public private(set) var results: [Item]
    @Published public private(set) var isSearching: Bool
    @Published public private(set) var lastErrorDescription: String?

    public let index: HangulSearchIndex<Item>
    public var options: HangulSearchUIOptions

    private var searchTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(
        index: HangulSearchIndex<Item>,
        options: HangulSearchUIOptions = .default,
        initialQuery: String = ""
    ) {
        self.index = index
        self.options = options
        self.query = initialQuery
        self.results = []
        self.isSearching = false
        self.lastErrorDescription = nil
    }

    public func submit(_ rawQuery: String, immediate: Bool = false) {
        let normalized = normalizedQuery(rawQuery)
        query = normalized

        generation &+= 1
        let token = generation

        searchTask?.cancel()
        searchTask = nil
        lastErrorDescription = nil

        guard shouldSearch(for: normalized) else {
            isSearching = false
            if normalized.isEmpty && options.clearResultsWhenQueryEmpty {
                results = []
            }
            return
        }

        isSearching = true
        let capturedOptions = options
        let debounceNs = immediate ? 0 : UInt64(capturedOptions.debounceMilliseconds) * 1_000_000
        let searchQuery = normalized

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                if debounceNs > 0 {
                    try await Task.sleep(nanoseconds: debounceNs)
                }
                try Task.checkCancellation()

                var found = try await index.search(searchQuery, mode: capturedOptions.mode)
                if found.isEmpty && capturedOptions.fallbackToSimilarityWhenNoMatch {
                    let scored = try await index.searchSimilar(searchQuery, options: capturedOptions.similarityOptions)
                    found = scored.map(\.item)
                }

                if let maxResults = capturedOptions.maxResults, found.count > maxResults {
                    found = Array(found.prefix(maxResults))
                }

                finishSearch(token: token, results: found, errorDescription: nil)
            } catch is CancellationError {
                finishSearch(token: token, results: nil, errorDescription: nil)
            } catch {
                finishSearch(token: token, results: nil, errorDescription: error.localizedDescription)
            }
        }
    }

    public func refresh(immediate: Bool = true) {
        submit(query, immediate: immediate)
    }

    public func cancel() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    public func clear() {
        cancel()
        query = ""
        results = []
        lastErrorDescription = nil
    }

    private func finishSearch(token: UInt64, results: [Item]?, errorDescription: String?) {
        guard token == generation else { return }
        isSearching = false
        if let results {
            self.results = results
        }
        self.lastErrorDescription = errorDescription
    }

    private func normalizedQuery(_ rawQuery: String) -> String {
        if options.trimWhitespace {
            return rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rawQuery
    }

    private func shouldSearch(for query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return query.count >= options.minimumQueryLength
    }
}
