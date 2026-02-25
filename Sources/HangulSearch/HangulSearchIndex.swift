import Foundation
import HangulCore

public final class HangulSearchIndex<Item>: @unchecked Sendable {
    private let items: [Item]
    private let rawKeys: [String]
    private let normalizedRawKeys: [String]
    private let policy: SearchPolicy
    private let allIndices: [Int]

    private let precomputedKeys: [String]?
    private let ngramIndex: [String: [Int]]?

    private let queryCache: LRUCache<String, [Int]>?
    private let lazyMaterializer: LazyKeyMaterializer?
    private let telemetry: SearchTelemetry

    private struct SimilarityCandidate {
        let index: Int
        let coarseScore: Double
        let isStrong: Bool
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
        self.items = items
        self.rawKeys = items.map { $0[keyPath: keyPath] }
        self.normalizedRawKeys = self.rawKeys.map(Self.normalizedSearchToken)
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
            let keys = rawKeys.map { Hangul.getChoseong($0, options: policy.choseongOptions) }
            self.precomputedKeys = keys
            self.ngramIndex = nil
            self.lazyMaterializer = nil
        case .lazyCache:
            self.precomputedKeys = nil
            self.ngramIndex = nil
            let materializer = LazyKeyMaterializer()
            self.lazyMaterializer = materializer
            if policy.lazyWarmup == .background {
                materializer.startBackgroundBuild(rawKeys: rawKeys, options: policy.choseongOptions)
            }
        case let .ngram(k):
            let effectiveK = max(2, min(3, k))
            let keys = rawKeys.map { Hangul.getChoseong($0, options: policy.choseongOptions) }
            self.precomputedKeys = keys
            self.ngramIndex = Self.buildNgramIndex(keys: keys, k: effectiveK)
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

        let normalizedQuery = boundedNormalizedChoseongQuery(query)
        guard !normalizedQuery.isEmpty else { return output }

        let cacheKey = mode.rawValue + "|" + normalizedQuery
        if let cached = queryCache?.get(cacheKey) {
            usedCache = true
            output = cached.map { items[$0] }
            return output
        }

        let candidates = candidateIndicesForSearch(query: normalizedQuery)
        let matched: [Int]

        switch policy.indexStrategy {
        case .precompute, .ngram:
            guard let precomputedKeys else {
                matched = []
                break
            }
            matched = filterIndices(candidates: candidates, query: normalizedQuery, mode: mode, keys: precomputedKeys)
        case .lazyCache:
            if let lazyMaterializer {
                let keys = lazyMaterializer.getOrBuild(rawKeys: rawKeys, options: policy.choseongOptions)
                matched = filterIndices(candidates: candidates, query: normalizedQuery, mode: mode, keys: keys)
            } else {
                matched = filterIndices(candidates: candidates, query: normalizedQuery, mode: mode) { index in
                    Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
                }
            }
        }

        queryCache?.set(cacheKey, value: matched)
        output = matched.map { items[$0] }
        return output
    }

    public func search(_ query: String, mode: MatchMode = .contains) async throws -> [Item] {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var usedCache = false

        do {
            try Task.checkCancellation()

            let normalizedQuery = boundedNormalizedChoseongQuery(query)
            guard !normalizedQuery.isEmpty else {
                telemetry.recordAsyncSearchSuccess(
                    latencyNs: Self.elapsedNanoseconds(since: startedAt),
                    cacheHit: false,
                    resultCount: 0
                )
                return []
            }

            let cacheKey = mode.rawValue + "|" + normalizedQuery
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

            let candidates = candidateIndicesForSearch(query: normalizedQuery)
            let matched: [Int]

            switch policy.indexStrategy {
            case .precompute, .ngram:
                guard let precomputedKeys else {
                    matched = []
                    break
                }
                matched = try filterIndicesCancellable(candidates: candidates, query: normalizedQuery, mode: mode) { index in
                    precomputedKeys[index]
                }
            case .lazyCache:
                if let lazyMaterializer, let readyKeys = lazyMaterializer.readyKeys() {
                    matched = try filterIndicesCancellable(candidates: candidates, query: normalizedQuery, mode: mode) { index in
                        readyKeys[index]
                    }
                } else {
                    var materialized = Array(repeating: "", count: rawKeys.count)
                    var localMatched: [Int] = []
                    localMatched.reserveCapacity(min(candidates.count, 64))

                    for (offset, index) in candidates.enumerated() {
                        if offset % 16 == 0 {
                            try Task.checkCancellation()
                        }

                        let key = Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
                        materialized[index] = key
                        if mode.matches(text: key, query: normalizedQuery) {
                            localMatched.append(index)
                        }
                    }

                    lazyMaterializer?.storeBuiltKeysIfNeeded(materialized)
                    matched = localMatched
                }
            }

            queryCache?.set(cacheKey, value: matched)
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

        let choseongKeys = choseongKeysForScoring().map(Self.normalizedSearchToken)
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
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            try Task.checkCancellation()

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

            let choseongKeys = try choseongKeysForScoringCancellable().map(Self.normalizedSearchToken)
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

        let choseongKeys = choseongKeysForScoring().map(Self.normalizedSearchToken)
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
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            try Task.checkCancellation()

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

            let choseongKeys = try choseongKeysForScoringCancellable().map(Self.normalizedSearchToken)
            let ranked = try rankSimilarImpl(
                variants: variants,
                choseongKeys: choseongKeys,
                options: options,
                cancellationCheck: { try Task.checkCancellation() }
            )
            let output = makeExplainedResults(from: ranked, choseongKeys: choseongKeys, options: options)
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
        let lookupQuery = choseongQuery.isEmpty ? variant : choseongQuery
        let base = candidateIndicesForSearch(query: lookupQuery)

        let targetCandidateCount = min(
            base.count,
            max(options.candidateLimitPerVariant, max(1, options.limit) * 10)
        )
        guard base.count > targetCandidateCount else {
            return base.map { SimilarityCandidate(index: $0, coarseScore: 1, isStrong: true) }
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

    private func prefilterCandidates(
        base: [Int],
        variant: String,
        choseongQuery: String,
        normalizedChoseongKeys: [String],
        limit: Int,
        cancellationCheck: (() throws -> Void)?
    ) rethrows -> [SimilarityCandidate] {
        let normalizedQuery = Self.normalizedSearchToken(variant)
        let normalizedChoseongQuery = Self.normalizedSearchToken(choseongQuery)

        var strong: [SimilarityCandidate] = []
        strong.reserveCapacity(min(limit, base.count))

        var coarse: [SimilarityCandidate] = []
        coarse.reserveCapacity(min(base.count, limit * 2))

        for (offset, index) in base.enumerated() {
            if offset % 64 == 0 {
                try cancellationCheck?()
            }

            let key = normalizedRawKeys[index]
            let choseongKey = normalizedChoseongKeys[index]

            let strongRaw = !normalizedQuery.isEmpty && (
                key == normalizedQuery || key.hasPrefix(normalizedQuery) || key.contains(normalizedQuery)
            )

            let strongChoseong = !normalizedChoseongQuery.isEmpty && (
                choseongKey == normalizedChoseongQuery ||
                choseongKey.hasPrefix(normalizedChoseongQuery) ||
                choseongKey.contains(normalizedChoseongQuery)
            )

            if strongRaw || strongChoseong {
                strong.append(SimilarityCandidate(index: index, coarseScore: 1, isStrong: true))
                continue
            }

            let score = SimilarityScorer.coarseSimilarity(
                query: normalizedQuery,
                choseongQuery: normalizedChoseongQuery,
                key: key,
                choseongKey: choseongKey
            )
            if score > 0 {
                coarse.append(SimilarityCandidate(index: index, coarseScore: score, isStrong: false))
            }
        }

        strong.sort {
            if normalizedRawKeys[$0.index].count == normalizedRawKeys[$1.index].count {
                return $0.index < $1.index
            }
            return normalizedRawKeys[$0.index].count < normalizedRawKeys[$1.index].count
        }

        if strong.count >= limit {
            return Array(strong.prefix(limit))
        }

        coarse.sort { lhs, rhs in
            if lhs.coarseScore == rhs.coarseScore {
                return lhs.index < rhs.index
            }
            return lhs.coarseScore > rhs.coarseScore
        }

        let remaining = limit - strong.count
        var result = strong
        result.reserveCapacity(limit)
        result.append(contentsOf: coarse.prefix(remaining))

        if result.isEmpty {
            return Array(base.prefix(limit)).map { SimilarityCandidate(index: $0, coarseScore: 0, isStrong: false) }
        }

        return result
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
        let coarseCutoff = max(0.05, initialScoreGate * 0.6)

        if cancellationCheck == nil {
            let workerCount = min(
                ProcessInfo.processInfo.activeProcessorCount,
                max(1, candidates.count / 256)
            )
            if workerCount > 1 {
                return computeVariantScoresParallel(
                    variant: variant,
                    choseongQuery: choseongQuery,
                    normalizedChoseongKeys: normalizedChoseongKeys,
                    candidates: candidates,
                    options: options,
                    coarseCutoff: coarseCutoff,
                    workerCount: workerCount
                )
            }
        }

        var entries: [(index: Int, breakdown: SimilarityScoreBreakdown)] = []
        entries.reserveCapacity(min(candidates.count, max(1, options.limit) * 4))
        var localScoreGate = initialScoreGate
        let localTrimTarget = max(max(1, options.limit) * 4, 128)

        for (offset, candidate) in candidates.enumerated() {
            if offset % 16 == 0 {
                try cancellationCheck?()
            }

            if !candidate.isStrong && candidate.coarseScore < coarseCutoff {
                continue
            }

            let breakdown = SimilarityScorer.score(
                query: variant,
                target: rawKeys[candidate.index],
                queryChoseong: choseongQuery,
                targetChoseong: normalizedChoseongKeys[candidate.index],
                options: options
            )

            let total = breakdown.totalScore
            if total < options.minimumScore || total < localScoreGate {
                continue
            }
            entries.append((candidate.index, breakdown))

            if entries.count > localTrimTarget {
                entries.sort {
                    if $0.breakdown.totalScore == $1.breakdown.totalScore {
                        return $0.index < $1.index
                    }
                    return $0.breakdown.totalScore > $1.breakdown.totalScore
                }
                entries.removeSubrange(localTrimTarget..<entries.count)
            }

            localScoreGate = max(
                initialScoreGate,
                kthScore(entries: entries, k: max(1, options.limit), minimum: options.minimumScore)
            )
        }

        return entries
    }

    private func computeVariantScoresParallel(
        variant: String,
        choseongQuery: String,
        normalizedChoseongKeys: [String],
        candidates: [SimilarityCandidate],
        options: SimilarityOptions,
        coarseCutoff: Double,
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
            var local: [(index: Int, breakdown: SimilarityScoreBreakdown)] = []
            local.reserveCapacity(end - start)

            for i in start..<end {
                let candidate = candidates[i]
                if !candidate.isStrong && candidate.coarseScore < coarseCutoff {
                    continue
                }

                let breakdown = SimilarityScorer.score(
                    query: variant,
                    target: rawKeys[candidate.index],
                    queryChoseong: choseongQuery,
                    targetChoseong: normalizedChoseongKeys[candidate.index],
                    options: options
                )

                if breakdown.totalScore >= options.minimumScore {
                    local.append((candidate.index, breakdown))
                }
            }

            guard !local.isEmpty else { return }
            collector.append(local)
        }

        return collector.snapshot()
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
        options: SimilarityOptions
    ) -> [ExplainedSearchResult<Item>] {
        var results: [ExplainedSearchResult<Item>] = []
        results.reserveCapacity(ranked.count)

        for entry in ranked {
            let queryChoseong = Self.normalizedSearchToken(
                Hangul.getChoseong(entry.variant, options: policy.choseongOptions)
            )
            let explained = SimilarityScorer.explain(
                query: entry.variant,
                target: rawKeys[entry.index],
                queryChoseong: queryChoseong,
                targetChoseong: choseongKeys[entry.index],
                options: options
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

    private func boundedRawQuery(_ query: String) -> String {
        guard let maxQueryLength = policy.maxQueryLength else {
            return query
        }
        guard query.count > maxQueryLength else {
            return query
        }
        return String(query.prefix(maxQueryLength))
    }

    private func boundedNormalizedChoseongQuery(_ query: String) -> String {
        let raw = boundedRawQuery(query)
        return Hangul.getChoseong(raw, options: policy.choseongOptions)
    }

    private func boundedQueryVariants(for query: String, includeLayoutVariants: Bool) -> [String] {
        SimilarityScorer.queryVariants(for: boundedRawQuery(query), includeLayoutVariants: includeLayoutVariants)
            .map(boundedRawQuery)
    }

    private func choseongKeysForScoring() -> [String] {
        switch policy.indexStrategy {
        case .precompute, .ngram:
            return precomputedKeys ?? rawKeys.map { Hangul.getChoseong($0, options: policy.choseongOptions) }
        case .lazyCache:
            if let lazyMaterializer {
                return lazyMaterializer.getOrBuild(rawKeys: rawKeys, options: policy.choseongOptions)
            }
            return rawKeys.map { Hangul.getChoseong($0, options: policy.choseongOptions) }
        }
    }

    private func choseongKeysForScoringCancellable() throws -> [String] {
        switch policy.indexStrategy {
        case .precompute, .ngram:
            return precomputedKeys ?? rawKeys.map { Hangul.getChoseong($0, options: policy.choseongOptions) }
        case .lazyCache:
            if let lazyMaterializer, let ready = lazyMaterializer.readyKeys() {
                return ready
            }

            var built = Array(repeating: "", count: rawKeys.count)
            for (offset, index) in rawKeys.indices.enumerated() {
                if offset % 16 == 0 {
                    try Task.checkCancellation()
                }
                built[index] = Hangul.getChoseong(rawKeys[index], options: policy.choseongOptions)
            }

            lazyMaterializer?.storeBuiltKeysIfNeeded(built)
            return built
        }
    }

    private func candidateIndices(for query: String) -> [Int] {
        guard case let .ngram(rawK) = policy.indexStrategy,
              let ngramIndex else {
            return allIndices
        }

        let k = max(2, min(3, rawK))
        let grams = Self.makeNgrams(text: query, k: k)
        guard !grams.isEmpty else {
            return allIndices
        }

        var candidateSet: Set<Int>?
        for gram in Set(grams) {
            guard let posting = ngramIndex[gram] else {
                return []
            }

            let postingSet = Set(posting)
            if var existing = candidateSet {
                existing.formIntersection(postingSet)
                if existing.isEmpty { return [] }
                candidateSet = existing
            } else {
                candidateSet = postingSet
            }
        }

        return candidateSet?.sorted() ?? allIndices
    }

    private func candidateIndicesForSearch(query: String) -> [Int] {
        applyCandidateScanLimit(candidateIndices(for: query))
    }

    private func applyCandidateScanLimit(_ candidates: [Int]) -> [Int] {
        guard let maxCandidateScan = policy.maxCandidateScan,
              candidates.count > maxCandidateScan else {
            return candidates
        }
        return Array(candidates.prefix(maxCandidateScan))
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
}
