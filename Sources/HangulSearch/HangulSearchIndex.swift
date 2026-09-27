import Foundation
import HangulCore

public final class HangulSearchIndex<Item: Sendable>: @unchecked Sendable {
    private let items: [Item]
    private let rawKeys: [String]
    private let normalizedRawKeys: [String]
    private let normalizedCompactedRawKeys: [String]
    private let policy: SearchPolicy
    private let allIndices: [Int]

    private let precomputedKeys: [String]?
    private let ngramChoseongIndex: [String: [Int]]?
    private let ngramRawIndex: [String: [Int]]?
    private let ngramRawCompactedIndex: [String: [Int]]?

    private let queryCache: LRUCache<String, [Int]>?
    private let lazyMaterializer: LazyKeyMaterializer?
    private let telemetry: SearchTelemetry

    private enum QueryMatchTarget: String {
        case raw
        case choseong
    }

    private struct SearchQueryContext {
        let normalizedQuery: String
        let normalizedCompactedQuery: String
        let target: QueryMatchTarget

        var cacheToken: String {
            target.rawValue + "|" + normalizedQuery + "|" + normalizedCompactedQuery
        }
    }

    private struct SimilarityCandidate {
        let index: Int
        let coarseScore: Double
        let priority: Int
        let length: Int
    }

    private struct RankedSimilarEntry {
        let index: Int
        let breakdown: SimilarityScoreBreakdown
        let variant: String
    }

    private final class ParallelScoreCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(index: Int, breakdown: SimilarityScoreBreakdown)] = []

        init(capacity: Int) {
            values.reserveCapacity(capacity)
        }

        func append(_ entries: [(index: Int, breakdown: SimilarityScoreBreakdown)]) {
            lock.lock()
            values.append(contentsOf: entries)
            lock.unlock()
        }

        func snapshot() -> [(index: Int, breakdown: SimilarityScoreBreakdown)] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    public init(items: [Item], keyPath: KeyPath<Item, String>, policy: SearchPolicy = .default) {
        let policy = policy.validated()
        self.items = items
        self.rawKeys = items.map { $0[keyPath: keyPath] }
        self.normalizedRawKeys = self.rawKeys.map(Self.normalizedSearchToken)
        self.normalizedCompactedRawKeys = self.normalizedRawKeys.map(Self.compactedSearchToken)
        self.policy = policy
        self.allIndices = Array(items.indices)
        self.telemetry = SearchTelemetry()

        switch policy.cache {
        case .none:
            self.queryCache = nil
        case let .lru(capacity):
            self.queryCache = LRUCache<String, [Int]>(capacity: capacity)
        }

        switch policy.indexStrategy {
        case .precompute:
            let keys = rawKeys.map { Self.normalizedSearchToken(Hangul.getChoseong($0, options: policy.choseongOptions)) }
            self.precomputedKeys = keys
            self.ngramChoseongIndex = nil
            self.ngramRawIndex = nil
            self.ngramRawCompactedIndex = nil
            self.lazyMaterializer = nil
        case .lazyCache:
            self.precomputedKeys = nil
            self.ngramChoseongIndex = nil
            self.ngramRawIndex = nil
            self.ngramRawCompactedIndex = nil
            let materializer = LazyKeyMaterializer()
            self.lazyMaterializer = materializer
            if policy.lazyWarmup == .background {
                materializer.startBackgroundBuild(rawKeys: rawKeys, options: policy.choseongOptions)
            }
        case let .ngram(k):
            let effectiveK = max(2, min(3, k))
            let keys = rawKeys.map { Self.normalizedSearchToken(Hangul.getChoseong($0, options: policy.choseongOptions)) }
            self.precomputedKeys = keys
            self.ngramChoseongIndex = Self.buildNgramIndex(keys: keys, k: effectiveK)
            self.ngramRawIndex = Self.buildNgramIndex(keys: self.normalizedRawKeys, k: effectiveK)
            self.ngramRawCompactedIndex = Self.buildNgramIndex(keys: self.normalizedCompactedRawKeys, k: effectiveK)
            self.lazyMaterializer = nil
        }
    }

    public func search(_ query: String, mode: MatchMode = .contains) -> [Item] {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var usedCache = false
        var output: [Item] = []

        defer {
            telemetry.recordSyncSearch(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                cacheHit: usedCache,
                resultCount: output.count
            )
        }

        let queryContext = boundedSearchQueryContext(query)
        guard !queryContext.normalizedQuery.isEmpty else { return output }

        let cacheKey = mode.rawValue + "|" + queryContext.cacheToken
        if let cached = queryCache?.get(cacheKey) {
            usedCache = true
            output = cached.map { items[$0] }
            return output
        }

        let candidates = candidateIndicesForSearch(
            query: queryContext.normalizedQuery,
            compactedQuery: queryContext.normalizedCompactedQuery,
            target: queryContext.target
        )
        let matched: [Int]

        switch policy.indexStrategy {
        case .precompute, .ngram:
            switch queryContext.target {
            case .raw:
                matched = filterRawIndices(
                    candidates: candidates,
                    query: queryContext.normalizedQuery,
                    compactedQuery: queryContext.normalizedCompactedQuery,
                    mode: mode
                )
            case .choseong:
                guard let precomputedKeys else {
                    matched = []
                    break
                }
                matched = filterIndices(
                    candidates: candidates,
                    query: queryContext.normalizedQuery,
                    mode: mode,
                    keys: precomputedKeys
                )
            }
        case .lazyCache:
            switch queryContext.target {
            case .raw:
                matched = filterRawIndices(
                    candidates: candidates,
                    query: queryContext.normalizedQuery,
                    compactedQuery: queryContext.normalizedCompactedQuery,
                    mode: mode
                )
            case .choseong:
                if let lazyMaterializer {
                    let keys = lazyMaterializer.getOrBuild(rawKeys: rawKeys, options: policy.choseongOptions)
                    matched = filterIndices(
                        candidates: candidates,
                        query: queryContext.normalizedQuery,
                        mode: mode,
                        keys: keys
                    )
                } else {
                    matched = filterIndices(
                        candidates: candidates,
                        query: queryContext.normalizedQuery,
                        mode: mode
                    ) { index in
                        Self.normalizedSearchToken(
                            Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
                        )
                    }
                }
            }
        }

        storeQueryCache(cacheKey: cacheKey, matchedIndices: matched)
        output = matched.map { items[$0] }
        return output
    }

    public func search(_ query: String, mode: MatchMode = .contains) async throws -> [Item] {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var usedCache = false

        do {
            try Task.checkCancellation()
            await Task.yield()

            let queryContext = boundedSearchQueryContext(query)
            guard !queryContext.normalizedQuery.isEmpty else {
                telemetry.recordAsyncSearchSuccess(
                    latencyNs: Self.elapsedNanoseconds(since: startedAt),
                    cacheHit: false,
                    resultCount: 0
                )
                return []
            }

            let cacheKey = mode.rawValue + "|" + queryContext.cacheToken
            if let cached = queryCache?.get(cacheKey) {
                usedCache = true
                let output = cached.map { items[$0] }
                telemetry.recordAsyncSearchSuccess(
                    latencyNs: Self.elapsedNanoseconds(since: startedAt),
                    cacheHit: true,
                    resultCount: output.count
                )
                return output
            }

            let candidates = candidateIndicesForSearch(
                query: queryContext.normalizedQuery,
                compactedQuery: queryContext.normalizedCompactedQuery,
                target: queryContext.target
            )
            let matched: [Int]

            switch policy.indexStrategy {
            case .precompute, .ngram:
                switch queryContext.target {
                case .raw:
                    matched = try filterRawIndicesCancellable(
                        candidates: candidates,
                        query: queryContext.normalizedQuery,
                        compactedQuery: queryContext.normalizedCompactedQuery,
                        mode: mode
                    )
                case .choseong:
                    guard let precomputedKeys else {
                        matched = []
                        break
                    }
                    matched = try filterIndicesCancellable(
                        candidates: candidates,
                        query: queryContext.normalizedQuery,
                        mode: mode
                    ) { index in
                        precomputedKeys[index]
                    }
                }
            case .lazyCache:
                switch queryContext.target {
                case .raw:
                    matched = try filterRawIndicesCancellable(
                        candidates: candidates,
                        query: queryContext.normalizedQuery,
                        compactedQuery: queryContext.normalizedCompactedQuery,
                        mode: mode
                    )
                case .choseong:
                    if let lazyMaterializer, let readyKeys = lazyMaterializer.readyKeys() {
                        matched = try filterIndicesCancellable(
                            candidates: candidates,
                            query: queryContext.normalizedQuery,
                            mode: mode
                        ) { index in
                            readyKeys[index]
                        }
                    } else {
                        let shouldPersistFullMaterialization =
                            candidates.count == rawKeys.count && candidates.elementsEqual(allIndices)
                        var materialized: [String]? = shouldPersistFullMaterialization
                            ? Array(repeating: "", count: rawKeys.count)
                            : nil
                        var localMatched: [Int] = []
                        localMatched.reserveCapacity(min(candidates.count, 64))

                        for (offset, index) in candidates.enumerated() {
                            if offset % 16 == 0 {
                                try Task.checkCancellation()
                            }

                            let key = Self.normalizedSearchToken(
                                Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
                            )
                            if shouldPersistFullMaterialization {
                                materialized?[index] = key
                            }
                            if mode.matches(text: key, query: queryContext.normalizedQuery) {
                                localMatched.append(index)
                            }
                        }

                        // Persist lazy materialization only when full key coverage is guaranteed.
                        // Storing partial arrays can poison future lookups with empty keys.
                        if shouldPersistFullMaterialization, let materialized {
                            lazyMaterializer?.storeBuiltKeysIfNeeded(materialized)
                        } else if policy.lazyWarmup == .background {
                            lazyMaterializer?.startBackgroundBuild(rawKeys: rawKeys, options: policy.choseongOptions)
                        }
                        matched = localMatched
                    }
                }
            }

            storeQueryCache(cacheKey: cacheKey, matchedIndices: matched)
            let output = matched.map { items[$0] }
            telemetry.recordAsyncSearchSuccess(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                cacheHit: usedCache,
                resultCount: output.count
            )
            return output
        } catch let error as CancellationError {
            telemetry.recordAsyncSearchCancelled(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        } catch {
            telemetry.recordAsyncSearchFailure(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        }
    }

    public func searchSimilar(
        _ query: String,
        options: SimilarityOptions = .default
    ) -> [ScoredSearchResult<Item>] {
        let options = options.validated()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var output: [ScoredSearchResult<Item>] = []

        defer {
            telemetry.recordSyncSimilar(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                resultCount: output.count
            )
        }

        let variants = boundedQueryVariants(
            for: query,
            includeLayoutVariants: options.includeLayoutVariants
        )
        guard !variants.isEmpty else { return output }

        let choseongKeys = choseongKeysForScoring()
        let ranked = rankSimilarImpl(
            variants: variants,
            choseongKeys: choseongKeys,
            options: options,
            cancellationCheck: nil
        )
        output = makeScoredResults(from: ranked)
        return output
    }

    public func searchSimilar(
        _ query: String,
        options: SimilarityOptions = .default
    ) async throws -> [ScoredSearchResult<Item>] {
        let options = options.validated()
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            try Task.checkCancellation()
            await Task.yield()

            let variants = boundedQueryVariants(
                for: query,
                includeLayoutVariants: options.includeLayoutVariants
            )
            guard !variants.isEmpty else {
                telemetry.recordAsyncSimilarSuccess(
                    latencyNs: Self.elapsedNanoseconds(since: startedAt),
                    resultCount: 0
                )
                return []
            }

            let choseongKeys = try choseongKeysForScoringCancellable()
            let ranked = try rankSimilarImpl(
                variants: variants,
                choseongKeys: choseongKeys,
                options: options,
                cancellationCheck: { try Task.checkCancellation() }
            )
            let output = makeScoredResults(from: ranked)
            telemetry.recordAsyncSimilarSuccess(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                resultCount: output.count
            )
            return output
        } catch let error as CancellationError {
            telemetry.recordAsyncSimilarCancelled(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        } catch {
            telemetry.recordAsyncSimilarFailure(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        }
    }

    public func explainSimilar(
        _ query: String,
        options: SimilarityOptions = .default
    ) -> [ExplainedSearchResult<Item>] {
        let options = options.validated()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var output: [ExplainedSearchResult<Item>] = []

        defer {
            telemetry.recordSyncExplain(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                resultCount: output.count
            )
        }

        let variants = boundedQueryVariants(
            for: query,
            includeLayoutVariants: options.includeLayoutVariants
        )
        guard !variants.isEmpty else { return output }

        let choseongKeys = choseongKeysForScoring()
        let ranked = rankSimilarImpl(
            variants: variants,
            choseongKeys: choseongKeys,
            options: options,
            cancellationCheck: nil
        )
        output = makeExplainedResults(from: ranked, choseongKeys: choseongKeys, options: options)
        return output
    }

    public func explainSimilar(
        _ query: String,
        options: SimilarityOptions = .default
    ) async throws -> [ExplainedSearchResult<Item>] {
        let options = options.validated()
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            try Task.checkCancellation()
            await Task.yield()

            let variants = boundedQueryVariants(
                for: query,
                includeLayoutVariants: options.includeLayoutVariants
            )
            guard !variants.isEmpty else {
                telemetry.recordAsyncExplainSuccess(
                    latencyNs: Self.elapsedNanoseconds(since: startedAt),
                    resultCount: 0
                )
                return []
            }

            let choseongKeys = try choseongKeysForScoringCancellable()
            let ranked = try rankSimilarImpl(
                variants: variants,
                choseongKeys: choseongKeys,
                options: options,
                cancellationCheck: { try Task.checkCancellation() }
            )
            let output = try makeExplainedResults(from: ranked, choseongKeys: choseongKeys, options: options,
                                                 cancellationCheck: { try Task.checkCancellation() })
            telemetry.recordAsyncExplainSuccess(
                latencyNs: Self.elapsedNanoseconds(since: startedAt),
                resultCount: output.count
            )
            return output
        } catch let error as CancellationError {
            telemetry.recordAsyncExplainCancelled(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        } catch {
            telemetry.recordAsyncExplainFailure(latencyNs: Self.elapsedNanoseconds(since: startedAt))
            throw error
        }
    }

    public var count: Int {
        items.count
    }

    public func telemetrySnapshot() -> SearchTelemetrySnapshot {
        telemetry.snapshot()
    }

    public func resetTelemetry() {
        telemetry.reset()
    }

    private func rankSimilarImpl(
        variants: [String],
        choseongKeys: [String],
        options: SimilarityOptions,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [RankedSimilarEntry] {
        var bestScores: [Int: (breakdown: SimilarityScoreBreakdown, variant: String)] = [:]
        bestScores.reserveCapacity(min(items.count, 512))
        let normalizedChoseongKeys = choseongKeys
        let trimTarget = max(max(1, options.limit) * 6, 256)
        var scoreGate = options.minimumScore

        for variant in variants {
            try cancellationCheck?()

            let choseongQuery = Self.normalizedSearchToken(
                Hangul.getChoseong(variant, options: policy.choseongOptions)
            )
            let candidates = try similarityCandidates(
                variant: variant,
                choseongQuery: choseongQuery,
                normalizedChoseongKeys: normalizedChoseongKeys,
                options: options,
                cancellationCheck: cancellationCheck
            )
            if candidates.isEmpty {
                continue
            }

            let scored = try computeVariantScores(
                variant: variant,
                choseongQuery: choseongQuery,
                normalizedChoseongKeys: normalizedChoseongKeys,
                candidates: candidates,
                options: options,
                initialScoreGate: scoreGate,
                cancellationCheck: cancellationCheck
            )

            for (offset, entry) in scored.enumerated() {
                if offset % 32 == 0 {
                    try cancellationCheck?()
                }

                let total = entry.breakdown.totalScore
                if total < scoreGate {
                    continue
                }

                if let existing = bestScores[entry.index], existing.breakdown.totalScore >= total {
                    continue
                }
                bestScores[entry.index] = (entry.breakdown, variant)
            }

            if bestScores.count > trimTarget {
                trimBestScores(&bestScores, keep: trimTarget)
            }

            scoreGate = currentScoreGate(bestScores: bestScores, limit: options.limit, minimum: options.minimumScore)
        }

        guard !bestScores.isEmpty else { return [] }

        let sorted = bestScores.sorted { lhs, rhs in
            if lhs.value.breakdown.totalScore == rhs.value.breakdown.totalScore {
                return lhs.key < rhs.key
            }
            return lhs.value.breakdown.totalScore > rhs.value.breakdown.totalScore
        }

        let limit = max(1, options.limit)
        var entries: [RankedSimilarEntry] = []
        entries.reserveCapacity(min(limit, sorted.count))

        for entry in sorted.prefix(limit) {
            entries.append(
                RankedSimilarEntry(
                    index: entry.key,
                    breakdown: entry.value.breakdown,
                    variant: entry.value.variant
                )
            )
        }

        return entries
    }

    private func similarityCandidates(
        variant: String,
        choseongQuery: String,
        normalizedChoseongKeys: [String],
        options: SimilarityOptions,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [SimilarityCandidate] {
        let base = try fuzzyCandidateIndices(
            query: variant, choseong: choseongQuery,
            minimumCount: max(options.candidateLimitPerVariant, options.limit * 10),
            cancellationCheck: cancellationCheck
        )

        let targetCandidateCount = min(
            base.count,
            max(options.candidateLimitPerVariant, max(1, options.limit) * 10)
        )
        guard base.count > targetCandidateCount else {
            return base.map { SimilarityCandidate(index: $0, coarseScore: 1, priority: 0, length: 0) }
        }

        return try prefilterCandidates(
            base: base,
            variant: variant,
            choseongQuery: choseongQuery,
            normalizedChoseongKeys: normalizedChoseongKeys,
            limit: targetCandidateCount,
            cancellationCheck: cancellationCheck
        )
    }

    private func fuzzyCandidateIndices(
        query: String, choseong: String, minimumCount: Int,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [Int] {
        guard case let .ngram(k) = policy.indexStrategy else {
            return applyCandidateScanLimit(allIndices)
        }
        let compacted = Self.compactedSearchToken(Self.normalizedSearchToken(query))
        // Fuzzy retrieval needs a union, not the direct-match intersection.
        // Short queries and sparse postings fall back to a bounded scan.
        guard compacted.unicodeScalars.count >= k else { return applyCandidateScanLimit(allIndices) }
        var candidates: [Int] = []
        for (token, index) in [(compacted, ngramRawCompactedIndex), (choseong, ngramChoseongIndex)] {
            for gram in Set(Self.makeNgrams(text: token, k: k)) {
                try cancellationCheck?()
                if let posting = index?[gram] {
                    candidates = Self.sortedUnion(candidates, posting)
                }
            }
        }
        return applyCandidateScanLimit(candidates.count < minimumCount ? allIndices : candidates)
    }

    private func prefilterCandidates(
        base: [Int],
        variant: String,
        choseongQuery: String,
        normalizedChoseongKeys: [String],
        limit: Int,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [SimilarityCandidate] {
        let normalizedQuery = Self.compactedSearchToken(Self.normalizedSearchToken(variant))
        let normalizedChoseongQuery = Self.normalizedSearchToken(choseongQuery)
        let choseongOnly = Self.isChoseongOnlyQuery(normalizedQuery)

        let preparedCoarse = SimilarityScorer.CoarseQuery(normalizedChoseongQuery.isEmpty ? normalizedQuery : normalizedChoseongQuery)
        var candidates = BoundedTopK<SimilarityCandidate>(capacity: limit) {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.priority > 0, $0.length != $1.length { return $0.length < $1.length }
            if $0.coarseScore != $1.coarseScore { return $0.coarseScore > $1.coarseScore }
            return $0.index < $1.index
        }

        for (offset, index) in base.enumerated() {
            if offset % 64 == 0 {
                try cancellationCheck?()
            }

            let key = normalizedCompactedRawKeys[index]
            let choseongKey = normalizedChoseongKeys[index]

            let strongRaw = !normalizedQuery.isEmpty && (
                key == normalizedQuery || key.hasPrefix(normalizedQuery) || key.contains(normalizedQuery)
            )

            let strongChoseong = choseongOnly && !normalizedChoseongQuery.isEmpty && (
                choseongKey == normalizedChoseongQuery ||
                choseongKey.hasPrefix(normalizedChoseongQuery) ||
                choseongKey.contains(normalizedChoseongQuery)
            )

            if strongRaw || strongChoseong {
                candidates.insert(.init(index: index, coarseScore: 1,
                                        priority: key == normalizedQuery ? 2 : 1, length: key.unicodeScalars.count))
                continue
            }

            let score = preparedCoarse.score(normalizedChoseongQuery.isEmpty ? key : choseongKey)
            candidates.insert(.init(index: index, coarseScore: score, priority: 0, length: key.unicodeScalars.count))
        }

        return candidates.sorted()
    }

    private func computeVariantScores(
        variant: String,
        choseongQuery: String,
        normalizedChoseongKeys: [String],
        candidates: [SimilarityCandidate],
        options: SimilarityOptions,
        initialScoreGate: Double,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [(index: Int, breakdown: SimilarityScoreBreakdown)] {
        let preparedQuery = SimilarityScorer.prepareQuery(variant, choseong: choseongQuery, options: options)

        if cancellationCheck == nil {
            let workerCount = min(
                ProcessInfo.processInfo.activeProcessorCount,
                max(1, candidates.count / 256)
            )
            if workerCount > 1 {
                return computeVariantScoresParallel(
                    preparedQuery: preparedQuery,
                    normalizedChoseongKeys: normalizedChoseongKeys,
                    candidates: candidates,
                    options: options,
                    workerCount: workerCount
                )
            }
        }

        var entries = Self.scoreHeap(limit: options.limit)

        for (offset, candidate) in candidates.enumerated() {
            if offset % 16 == 0 {
                try cancellationCheck?()
            }

            let breakdown = try SimilarityScorer.score(
                query: preparedQuery,
                target: rawKeys[candidate.index],
                targetChoseong: normalizedChoseongKeys[candidate.index],
                options: options,
                cancellationCheck: cancellationCheck
            )

            let total = breakdown.totalScore
            if total < options.minimumScore || total < initialScoreGate {
                continue
            }
            entries.insert((candidate.index, breakdown))
        }

        return entries.sorted()
    }

    private func computeVariantScoresParallel(
        preparedQuery: SimilarityScorer.QueryFeatures,
        normalizedChoseongKeys: [String],
        candidates: [SimilarityCandidate],
        options: SimilarityOptions,
        workerCount: Int
    ) -> [(index: Int, breakdown: SimilarityScoreBreakdown)] {
        let chunkSize = (candidates.count + workerCount - 1) / workerCount
        let collector = ParallelScoreCollector(capacity: min(candidates.count, max(1, options.limit) * 8))

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let start = worker * chunkSize
            if start >= candidates.count {
                return
            }

            let end = min(candidates.count, start + chunkSize)
            var local = Self.scoreHeap(limit: options.limit)

            for i in start..<end {
                let candidate = candidates[i]
                let breakdown = SimilarityScorer.score(
                    query: preparedQuery,
                    target: rawKeys[candidate.index],
                    targetChoseong: normalizedChoseongKeys[candidate.index],
                    options: options
                )

                if breakdown.totalScore >= options.minimumScore {
                    local.insert((candidate.index, breakdown))
                }
            }

            collector.append(local.sorted())
        }

        return collector.snapshot()
    }

    private static func scoreHeap(limit: Int) -> BoundedTopK<(index: Int, breakdown: SimilarityScoreBreakdown)> {
        BoundedTopK(capacity: limit) {
            if $0.breakdown.totalScore == $1.breakdown.totalScore { return $0.index < $1.index }
            return $0.breakdown.totalScore > $1.breakdown.totalScore
        }
    }

    private func trimBestScores(
        _ bestScores: inout [Int: (breakdown: SimilarityScoreBreakdown, variant: String)],
        keep: Int
    ) {
        guard bestScores.count > keep else { return }

        let trimmed = bestScores.sorted { lhs, rhs in
            if lhs.value.breakdown.totalScore == rhs.value.breakdown.totalScore {
                return lhs.key < rhs.key
            }
            return lhs.value.breakdown.totalScore > rhs.value.breakdown.totalScore
        }
        .prefix(keep)

        var next: [Int: (breakdown: SimilarityScoreBreakdown, variant: String)] = [:]
        next.reserveCapacity(keep)
        for entry in trimmed {
            next[entry.key] = entry.value
        }
        bestScores = next
    }

    private func currentScoreGate(
        bestScores: [Int: (breakdown: SimilarityScoreBreakdown, variant: String)],
        limit: Int,
        minimum: Double
    ) -> Double {
        guard !bestScores.isEmpty else { return minimum }
        return kthScore(
            entries: bestScores.values.map { (index: 0, breakdown: $0.breakdown) },
            k: max(1, limit),
            minimum: minimum
        )
    }

    private func kthScore(
        entries: [(index: Int, breakdown: SimilarityScoreBreakdown)],
        k: Int,
        minimum: Double
    ) -> Double {
        guard entries.count >= k else { return minimum }
        let sorted = entries.map(\.breakdown.totalScore).sorted(by: >)
        return max(minimum, sorted[k - 1])
    }

    private func makeScoredResults(from ranked: [RankedSimilarEntry]) -> [ScoredSearchResult<Item>] {
        var results: [ScoredSearchResult<Item>] = []
        results.reserveCapacity(ranked.count)
        for entry in ranked {
            results.append(
                ScoredSearchResult(
                    item: items[entry.index],
                    breakdown: entry.breakdown,
                    matchedQuery: entry.variant,
                    matchedKey: rawKeys[entry.index]
                )
            )
        }
        return results
    }

    private func makeExplainedResults(
        from ranked: [RankedSimilarEntry],
        choseongKeys: [String],
        options: SimilarityOptions,
        cancellationCheck: (() throws -> Void)? = nil
    ) rethrows -> [ExplainedSearchResult<Item>] {
        var results: [ExplainedSearchResult<Item>] = []
        results.reserveCapacity(ranked.count)

        for entry in ranked {
            let queryChoseong = Self.normalizedSearchToken(
                Hangul.getChoseong(entry.variant, options: policy.choseongOptions)
            )
            let explained = try SimilarityScorer.explain(
                query: entry.variant,
                target: rawKeys[entry.index],
                queryChoseong: queryChoseong,
                targetChoseong: choseongKeys[entry.index],
                options: options,
                cancellationCheck: cancellationCheck
            )
            results.append(
                ExplainedSearchResult(
                    item: items[entry.index],
                    breakdown: explained.breakdown,
                    matchedQuery: entry.variant,
                    matchedKey: rawKeys[entry.index],
                    detail: explained.detail
                )
            )
        }

        return results
    }

    private static func normalizedSearchToken(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func compactedSearchToken(_ text: String) -> String {
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
            scalars.append(scalar)
        }

        return String(String.UnicodeScalarView(scalars))
    }

    private func boundedRawQuery(_ query: String) -> String {
        guard let maxQueryLength = policy.maxQueryLength else {
            return query
        }
        // A single grapheme can contain arbitrarily many combining scalars.
        let scalarBounded = String(String.UnicodeScalarView(query.unicodeScalars.prefix(maxQueryLength * 4)))
        return String(scalarBounded.precomposedStringWithCanonicalMapping.prefix(maxQueryLength))
    }

    private func boundedSearchQueryContext(_ query: String) -> SearchQueryContext {
        let bounded = boundedRawQuery(query)
        let normalizedRaw = Self.normalizedSearchToken(bounded)
        let compactedRaw = Self.compactedSearchToken(normalizedRaw)
        guard !compactedRaw.isEmpty else {
            return SearchQueryContext(normalizedQuery: "", normalizedCompactedQuery: "", target: .raw)
        }

        if Self.isChoseongOnlyQuery(normalizedRaw) {
            let choseong = Self.normalizedSearchToken(
                Hangul.getChoseong(bounded, options: policy.choseongOptions)
            )
            return SearchQueryContext(
                normalizedQuery: choseong,
                normalizedCompactedQuery: Self.compactedSearchToken(choseong),
                target: .choseong
            )
        }

        return SearchQueryContext(
            normalizedQuery: normalizedRaw,
            normalizedCompactedQuery: compactedRaw,
            target: .raw
        )
    }

    private func boundedQueryVariants(for query: String, includeLayoutVariants: Bool) -> [String] {
        SimilarityScorer.queryVariants(for: boundedRawQuery(query), includeLayoutVariants: includeLayoutVariants)
            .map(boundedRawQuery)
    }

    private func choseongKeysForScoring() -> [String] {
        switch policy.indexStrategy {
        case .precompute, .ngram:
            return precomputedKeys ?? rawKeys.map {
                Self.normalizedSearchToken(Hangul.getChoseong($0, options: policy.choseongOptions))
            }
        case .lazyCache:
            if let lazyMaterializer {
                return lazyMaterializer.getOrBuild(rawKeys: rawKeys, options: policy.choseongOptions)
            }
            return rawKeys.map {
                Self.normalizedSearchToken(Hangul.getChoseong($0, options: policy.choseongOptions))
            }
        }
    }

    private func choseongKeysForScoringCancellable() throws -> [String] {
        switch policy.indexStrategy {
        case .precompute, .ngram:
            return precomputedKeys ?? rawKeys.map {
                Self.normalizedSearchToken(Hangul.getChoseong($0, options: policy.choseongOptions))
            }
        case .lazyCache:
            if let lazyMaterializer, let ready = lazyMaterializer.readyKeys() {
                return ready
            }

            var built = Array(repeating: "", count: rawKeys.count)
            for (offset, index) in rawKeys.indices.enumerated() {
                if offset % 16 == 0 {
                    try Task.checkCancellation()
                }
                built[index] = Self.normalizedSearchToken(
                    Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
                )
            }

            lazyMaterializer?.storeBuiltKeysIfNeeded(built)
            return built
        }
    }

    private func candidateIndices(
        for query: String,
        compactedQuery: String,
        target: QueryMatchTarget
    ) -> [Int] {
        guard case let .ngram(rawK) = policy.indexStrategy else {
            return allIndices
        }

        let k = max(2, min(3, rawK))
        func candidateList(
            from index: [String: [Int]]?,
            queryToken: String
        ) -> [Int]? {
            guard let index else { return nil }

            let grams = Set(Self.makeNgrams(text: queryToken, k: k))
            guard !grams.isEmpty else { return nil }

            var postings: [[Int]] = []
            postings.reserveCapacity(grams.count)

            for gram in grams {
                guard let posting = index[gram] else {
                    return []
                }
                postings.append(posting)
            }

            postings.sort { $0.count < $1.count }
            guard var intersection = postings.first else { return [] }
            for posting in postings.dropFirst() {
                intersection = Self.sortedIntersection(intersection, posting)
                if intersection.isEmpty { return [] }
            }
            return intersection
        }

        switch target {
        case .choseong:
            guard let list = candidateList(from: ngramChoseongIndex, queryToken: query) else {
                return allIndices
            }
            return list
        case .raw:
            if !compactedQuery.isEmpty, compactedQuery.unicodeScalars.count < k {
                return allIndices
            }
            var union: [Int] = []
            var hasAnyList = false

            if let normalList = candidateList(from: ngramRawIndex, queryToken: query) {
                union = normalList
                hasAnyList = true
            }

            if let compactList = candidateList(from: ngramRawCompactedIndex, queryToken: compactedQuery) {
                union = hasAnyList ? Self.sortedUnion(union, compactList) : compactList
                hasAnyList = true
            }

            guard hasAnyList else { return allIndices }
            return union
        }
    }

    private func candidateIndicesForSearch(
        query: String,
        compactedQuery: String,
        target: QueryMatchTarget
    ) -> [Int] {
        applyCandidateScanLimit(
            candidateIndices(
                for: query,
                compactedQuery: compactedQuery,
                target: target
            )
        )
    }

    private static func isChoseongOnlyQuery(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }

        for scalar in token.unicodeScalars {
            if scalar.properties.isWhitespace {
                continue
            }
            if isChoseongScalar(scalar) {
                continue
            }
            return false
        }
        return true
    }

    private static func isChoseongScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x1112: // Hangul Jamo Choseong
            return true
        case 0x3131...0x314E: // Hangul Compatibility Jamo consonants
            return true
        case 0xA960...0xA97C: // Hangul Jamo Extended-A choseong
            return true
        case 0xFFA1...0xFFBE: // Halfwidth Hangul consonants
            return true
        default:
            return false
        }
    }

    private func applyCandidateScanLimit(_ candidates: [Int]) -> [Int] {
        guard let maxCandidateScan = policy.maxCandidateScan,
              candidates.count > maxCandidateScan else {
            return candidates
        }
        return Array(candidates.prefix(maxCandidateScan))
    }

    private func rawMatch(
        index: Int,
        query: String,
        compactedQuery: String,
        mode: MatchMode
    ) -> Bool {
        if mode.matches(text: normalizedRawKeys[index], query: query) {
            return true
        }
        if compactedQuery.isEmpty {
            return false
        }
        return mode.matches(text: normalizedCompactedRawKeys[index], query: compactedQuery)
    }

    private func filterRawIndices(
        candidates: [Int],
        query: String,
        compactedQuery: String,
        mode: MatchMode
    ) -> [Int] {
        var matched: [Int] = []
        matched.reserveCapacity(min(candidates.count, 64))

        for index in candidates {
            if rawMatch(index: index, query: query, compactedQuery: compactedQuery, mode: mode) {
                matched.append(index)
            }
        }

        return matched
    }

    private func filterRawIndicesCancellable(
        candidates: [Int],
        query: String,
        compactedQuery: String,
        mode: MatchMode
    ) throws -> [Int] {
        var matched: [Int] = []
        matched.reserveCapacity(min(candidates.count, 64))

        for (offset, index) in candidates.enumerated() {
            if offset % 16 == 0 {
                try Task.checkCancellation()
            }

            if rawMatch(index: index, query: query, compactedQuery: compactedQuery, mode: mode) {
                matched.append(index)
            }
        }

        return matched
    }

    private func filterIndices(candidates: [Int], query: String, mode: MatchMode, keys: [String]) -> [Int] {
        var matched: [Int] = []
        matched.reserveCapacity(min(candidates.count, 64))

        for index in candidates {
            if mode.matches(text: keys[index], query: query) {
                matched.append(index)
            }
        }

        return matched
    }

    private func filterIndices(
        candidates: [Int],
        query: String,
        mode: MatchMode,
        keyAt: (Int) -> String
    ) -> [Int] {
        var matched: [Int] = []
        matched.reserveCapacity(min(candidates.count, 64))

        for index in candidates {
            if mode.matches(text: keyAt(index), query: query) {
                matched.append(index)
            }
        }

        return matched
    }

    private func filterIndicesCancellable(
        candidates: [Int],
        query: String,
        mode: MatchMode,
        keyAt: (Int) -> String
    ) throws -> [Int] {
        var matched: [Int] = []
        matched.reserveCapacity(min(candidates.count, 64))

        for (offset, index) in candidates.enumerated() {
            if offset % 16 == 0 {
                try Task.checkCancellation()
            }

            if mode.matches(text: keyAt(index), query: query) {
                matched.append(index)
            }
        }

        return matched
    }

    private static func buildNgramIndex(keys: [String], k: Int) -> [String: [Int]] {
        var index: [String: [Int]] = [:]

        for (itemIndex, key) in keys.enumerated() {
            let grams = Set(makeNgrams(text: key, k: k))
            for gram in grams {
                index[gram, default: []].append(itemIndex)
            }
        }

        return index
    }

    private static func sortedIntersection(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        guard !lhs.isEmpty, !rhs.isEmpty else { return [] }

        var result: [Int] = []
        result.reserveCapacity(min(lhs.count, rhs.count))

        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < lhs.count, rightIndex < rhs.count {
            let left = lhs[leftIndex]
            let right = rhs[rightIndex]
            if left == right {
                result.append(left)
                leftIndex += 1
                rightIndex += 1
            } else if left < right {
                leftIndex += 1
            } else {
                rightIndex += 1
            }
        }

        return result
    }

    private static func sortedUnion(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }

        var result: [Int] = []
        result.reserveCapacity(lhs.count + rhs.count)

        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < lhs.count || rightIndex < rhs.count {
            if rightIndex >= rhs.count {
                result.append(lhs[leftIndex])
                leftIndex += 1
                continue
            }
            if leftIndex >= lhs.count {
                result.append(rhs[rightIndex])
                rightIndex += 1
                continue
            }

            let left = lhs[leftIndex]
            let right = rhs[rightIndex]
            if left == right {
                result.append(left)
                leftIndex += 1
                rightIndex += 1
            } else if left < right {
                result.append(left)
                leftIndex += 1
            } else {
                result.append(right)
                rightIndex += 1
            }
        }

        return result
    }

    private static func makeNgrams(text: String, k: Int) -> [String] {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= k else { return [] }

        var grams: [String] = []
        grams.reserveCapacity(scalars.count - k + 1)

        var start = 0
        while start + k <= scalars.count {
            let slice = scalars[start..<(start + k)]
            grams.append(String(String.UnicodeScalarView(slice)))
            start += 1
        }

        return grams
    }

    private static func elapsedNanoseconds(since start: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start ? (now - start) : 0
    }

    private func storeQueryCache(cacheKey: String, matchedIndices: [Int]) {
        guard let queryCache else { return }
        if let maxCachedResultCount = policy.maxCachedResultCount,
           matchedIndices.count > maxCachedResultCount {
            return
        }
        queryCache.set(cacheKey, value: matchedIndices)
    }
}
