import XCTest
@testable import HangulSearch

final class HangulSearchTests: XCTestCase {
    private struct Item: Sendable {
        let id: Int
        let name: String
    }

    private func benchmark(
        name: String,
        iterations: Int,
        warmup: Int = 0,
        block: () -> Void
    ) -> (meanMs: Double, stdMs: Double, minMs: Double, maxMs: Double, medianMs: Double, p95Ms: Double) {
        if warmup > 0 {
            for _ in 0..<warmup { block() }
        }

        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            block()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000.0)
        }

        let mean = samples.reduce(0, +) / Double(iterations)
        let variance = samples.reduce(0) { partial, value in
            let diff = value - mean
            return partial + (diff * diff)
        } / Double(iterations)
        let std = sqrt(variance)
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let p95Index = Int(Double(sorted.count - 1) * 0.95)
        let p95 = sorted[p95Index]

        print("[BENCH][Search][\(name)] mean=\(String(format: "%.3f", mean))ms std=\(String(format: "%.3f", std))ms median=\(String(format: "%.3f", median))ms p95=\(String(format: "%.3f", p95))ms min=\(String(format: "%.3f", samples.min() ?? 0))ms max=\(String(format: "%.3f", samples.max() ?? 0))ms")

        return (mean, std, samples.min() ?? 0, samples.max() ?? 0, median, p95)
    }

    private func evaluateRankingMetrics(
        index: HangulSearchIndex<Item>,
        queries: [(query: String, expectedID: Int)],
        limit: Int
    ) -> (top1: Double, top3: Double, mrr: Double) {
        var top1Hits = 0
        var top3Hits = 0
        var reciprocalSum = 0.0

        for test in queries {
            let ranked = index.searchSimilar(
                test.query,
                options: .init(limit: limit, candidateLimitPerVariant: 300, includeLayoutVariants: true)
            )

            if let first = ranked.first, first.item.id == test.expectedID {
                top1Hits += 1
            }

            if let rank = ranked.firstIndex(where: { $0.item.id == test.expectedID }) {
                if rank < 3 {
                    top3Hits += 1
                }
                reciprocalSum += 1.0 / Double(rank + 1)
            }
        }

        let count = Double(max(1, queries.count))
        return (
            top1: Double(top1Hits) / count,
            top3: Double(top3Hits) / count,
            mrr: reciprocalSum / count
        )
    }

    func testPrecomputeContainsSearch() {
        let items: [Item] = [
            .init(id: 1, name: "프론트엔드"),
            .init(id: 2, name: "백엔드"),
            .init(id: 3, name: "데이터"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let result = index.search("ㅍㄹㅌ")

        XCTAssertEqual(result.map(\.id), [1])
    }

    func testPrefixAndExactModes() {
        let items: [Item] = [
            .init(id: 1, name: "프론트"),
            .init(id: 2, name: "프론트엔드"),
            .init(id: 3, name: "백엔드"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .default)

        XCTAssertEqual(index.search("ㅍㄹㅌ", mode: .prefix).map(\.id), [1, 2])
        XCTAssertEqual(index.search("ㅍㄹㅌㅇㄷ", mode: .exact).map(\.id), [2])
    }

    func testAsyncSearchCancellation() async {
        let items = (0..<30_000).map { i in
            Item(id: i, name: i % 2 == 0 ? "프론트엔드\(i)" : "백엔드\(i)")
        }

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))

        let task = Task { try await index.search("ㅍ", mode: .contains) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchSmokeWithTenThousandItems() {
        let items = (0..<10_000).map { i in
            Item(id: i, name: i % 3 == 0 ? "프론트엔드\(i)" : "데이터\(i)")
        }

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let result = index.search("ㅍㄹㅌ")

        XCTAssertFalse(result.isEmpty)
    }

    func testSearchStrategyResultEquivalence() {
        let items = (0..<20_000).map { i in
            Item(id: i, name: i % 5 == 0 ? "프론트엔드\(i)" : (i % 2 == 0 ? "데이터\(i)" : "백엔드\(i)"))
        }

        let query = "ㅍㄹㅌㅇㄷ"

        let precompute = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let lazy = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .lazyCache, cache: .lru(capacity: 1024)))
        let ngram = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .ngram(k: 2)))

        let precomputeResult = precompute.search(query, mode: .contains).map(\.id)
        let lazyResult = lazy.search(query, mode: .contains).map(\.id)
        let ngramResult = ngram.search(query, mode: .contains).map(\.id)

        XCTAssertEqual(precomputeResult, lazyResult)
        XCTAssertEqual(precomputeResult, ngramResult)
    }

    func testSearchConcurrentDeterminism() async throws {
        let items = (0..<40_000).map { i in
            Item(id: i, name: i % 3 == 0 ? "프론트엔드\(i)" : "데이터\(i)")
        }
        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute, cache: .lru(capacity: 1024)))
        let baseline = try await index.search("ㅍㄹㅌ").map(\.id)

        try await withThrowingTaskGroup(of: [Int].self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await index.search("ㅍㄹㅌ").map(\.id)
                }
            }

            for try await ids in group {
                XCTAssertEqual(ids, baseline)
            }
        }
    }

    func testSearchPerformanceNumbers() {
        let items = (0..<60_000).map { i in
            Item(id: i, name: i % 7 == 0 ? "프론트엔드플랫폼\(i)" : (i % 3 == 0 ? "프론트엔드\(i)" : "데이터플랫폼\(i)"))
        }

        let buildPrecompute = benchmark(name: "build-precompute", iterations: 5) {
            _ = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        }

        let buildLazy = benchmark(name: "build-lazyCache", iterations: 5) {
            _ = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .lazyCache, cache: .lru(capacity: 2048)))
        }

        let buildNgram = benchmark(name: "build-ngram(k2)", iterations: 5) {
            _ = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .ngram(k: 2)))
        }

        let precompute = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute, cache: .none))
        let lazy = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .lazyCache, cache: .lru(capacity: 2048)))
        let lazyWarmup = HangulSearchIndex(
            items: items,
            keyPath: \.name,
            policy: .init(indexStrategy: .lazyCache, cache: .lru(capacity: 2048), lazyWarmup: .background)
        )
        let ngram = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .ngram(k: 2), cache: .none))

        let queryPrecompute = benchmark(name: "query-precompute", iterations: 30) {
            _ = precompute.search("ㅍㄹㅌㅇㄷ", mode: .contains)
        }

        let lazyColdStart = benchmark(name: "query-lazyCache-cold", iterations: 1) {
            _ = lazy.search("ㅍㄹㅌㅇㄷ", mode: .contains)
        }

        let queryLazyWarm = benchmark(name: "query-lazyCache-warm", iterations: 30, warmup: 1) {
            _ = lazy.search("ㅍㄹㅌㅇㄷ", mode: .contains)
        }

        // Give background warmup a short chance to progress.
        usleep(200_000)
        let queryLazyBackgroundWarm = benchmark(name: "query-lazyCache-backgroundWarm", iterations: 30, warmup: 1) {
            _ = lazyWarmup.search("ㅍㄹㅌㅇㄷ", mode: .contains)
        }

        let queryNgram = benchmark(name: "query-ngram(k2)", iterations: 30, warmup: 1) {
            _ = ngram.search("ㅍㄹㅌㅇㄷ", mode: .contains)
        }

        XCTAssertLessThan(buildPrecompute.meanMs, 1_500)
        XCTAssertLessThan(buildLazy.meanMs, 200)
        XCTAssertLessThan(buildNgram.meanMs, 2_500)
        XCTAssertLessThan(queryPrecompute.p95Ms, 120)
        XCTAssertLessThan(queryLazyWarm.p95Ms, 120)
        XCTAssertLessThan(queryNgram.p95Ms, 150)
        XCTAssertLessThan(lazyColdStart.maxMs, 8_000)
        XCTAssertLessThan(queryPrecompute.stdMs, 25)
        XCTAssertLessThan(queryLazyWarm.stdMs, 40)
        XCTAssertLessThan(queryNgram.stdMs, 35)
        XCTAssertLessThan(queryLazyBackgroundWarm.p95Ms, 120)
    }

    func testLazyBackgroundWarmupCorrectness() {
        let items = (0..<20_000).map { i in
            Item(id: i, name: i % 3 == 0 ? "프론트엔드\(i)" : "데이터\(i)")
        }

        let precompute = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let lazyWarmup = HangulSearchIndex(
            items: items,
            keyPath: \.name,
            policy: .init(indexStrategy: .lazyCache, cache: .lru(capacity: 1024), lazyWarmup: .background)
        )

        usleep(150_000)
        let expected = precompute.search("ㅍㄹㅌ", mode: .contains).map(\.id)
        let actual = lazyWarmup.search("ㅍㄹㅌ", mode: .contains).map(\.id)
        XCTAssertEqual(actual, expected)
    }

    func testSearchSimilarHandlesHangulTypos() {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "개발"),
            .init(id: 3, name: "결제"),
            .init(id: 4, name: "검사"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let results = index.searchSimilar("검삭", options: .init(limit: 3, minimumScore: 0.3))

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.item.id, 1)
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.5)
    }

    func testSearchSimilarHandlesLayoutMistype() {
        let items: [Item] = [
            .init(id: 1, name: "프론트엔드"),
            .init(id: 2, name: "백엔드"),
            .init(id: 3, name: "데이터"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))

        let withVariants = index.searchSimilar("vmfhsxmdpsem", options: .init(limit: 3, includeLayoutVariants: true))
        XCTAssertEqual(withVariants.first?.item.id, 1)

        let strict = index.searchSimilar(
            "vmfhsxmdpsem",
            options: .init(limit: 3, includeLayoutVariants: false, minimumScore: 0.85)
        )
        XCTAssertTrue(strict.isEmpty)
    }

    func testSearchSimilarHandlesHangulToEnglishMistype() {
        let items: [Item] = [
            .init(id: 1, name: "search"),
            .init(id: 2, name: "service"),
            .init(id: 3, name: "season"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let results = index.searchSimilar("ㄴㄷㅁㄱ초", options: .init(limit: 3, includeLayoutVariants: true))

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.item.id, 1)
        XCTAssertEqual(results.first?.matchedQuery.lowercased(), "search")
    }

    func testSearchSimilarAsync() async throws {
        let items = (0..<20_000).map { i in
            Item(id: i, name: i % 4 == 0 ? "프론트엔드\(i)" : "데이터플랫폼\(i)")
        }

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .ngram(k: 2)))
        let asyncResult = try await index.searchSimilar("vmfhsxm", options: .init(limit: 5, includeLayoutVariants: true))

        XCTAssertFalse(asyncResult.isEmpty)
        XCTAssertTrue(asyncResult.contains { $0.item.name.contains("프론트엔드") })
    }

    func testSearchSimilarCandidatePrefilterLimit() {
        var items: [Item] = []
        items.reserveCapacity(10_001)

        for i in 0..<10_000 {
            items.append(.init(id: i, name: "데이터플랫폼-\(i)"))
        }
        items.append(.init(id: 99_999, name: "프론트엔드"))

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let result = index.searchSimilar(
            "vmfhsxmdpsem",
            options: .init(limit: 3, candidateLimitPerVariant: 50, includeLayoutVariants: true)
        )

        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.first?.item.id, 99_999)
    }

    func testSearchSimilarScoreBreakdownExposure() {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "결제"),
            .init(id: 3, name: "검사"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let results = index.searchSimilar("검삭", options: .init(limit: 3, includeLayoutVariants: true))

        guard let first = results.first else {
            XCTFail("Expected similar results")
            return
        }

        XCTAssertEqual(first.item.id, 1)
        XCTAssertGreaterThan(first.breakdown.editDistanceSimilarity, 0)
        XCTAssertGreaterThan(first.breakdown.jamoSimilarity, 0)
        XCTAssertGreaterThan(first.breakdown.weightedCoreScore, 0)
        XCTAssertEqual(first.score, first.breakdown.totalScore, accuracy: 0.0001)
    }

    func testSearchSimilarEvaluationMetricsTopKAndMRR() {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "결제"),
            .init(id: 3, name: "프론트엔드"),
            .init(id: 4, name: "데이터베이스"),
            .init(id: 5, name: "네이버"),
            .init(id: 6, name: "search"),
            .init(id: 7, name: "로그인"),
            .init(id: 8, name: "회원가입"),
            .init(id: 9, name: "서비스"),
        ]

        let queries: [(query: String, expectedID: Int)] = [
            ("검삭", 1),
            ("결재", 2),
            ("vmfhsxmdpsem", 3),
            ("데이터베스", 4),
            ("spdlqj", 5),
            ("ㄴㄷㅁㄱ초", 6),
            ("로근인", 7),
            ("회언가입", 8),
            ("서비스", 9),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let metrics = evaluateRankingMetrics(index: index, queries: queries, limit: 5)

        print(
            "[EVAL][Search][similar] top1=\(String(format: "%.3f", metrics.top1)) " +
            "top3=\(String(format: "%.3f", metrics.top3)) mrr=\(String(format: "%.3f", metrics.mrr))"
        )

        XCTAssertGreaterThanOrEqual(metrics.top1, 0.75)
        XCTAssertGreaterThanOrEqual(metrics.top3, 0.95)
        XCTAssertGreaterThanOrEqual(metrics.mrr, 0.85)
    }

    func testExplainSimilarProvidesEvidence() {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "결제"),
            .init(id: 3, name: "검사"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let explained = index.explainSimilar("검삭", options: .init(limit: 1, includeLayoutVariants: true))

        guard let first = explained.first else {
            XCTFail("Expected explained result")
            return
        }

        XCTAssertEqual(first.item.id, 1)
        XCTAssertFalse(first.detail.normalizedQuery.isEmpty)
        XCTAssertFalse(first.detail.normalizedTarget.isEmpty)
        XCTAssertFalse(first.detail.jamoQuery.isEmpty)
        XCTAssertFalse(first.detail.jamoTarget.isEmpty)
        XCTAssertGreaterThanOrEqual(first.detail.editDistance, 0)
        XCTAssertGreaterThanOrEqual(first.detail.jamoEditDistance, 0)
        XCTAssertGreaterThanOrEqual(first.detail.keyboardDistance, 0)
        XCTAssertGreaterThanOrEqual(first.detail.jaccardUnionCount, first.detail.jaccardIntersectionCount)
        XCTAssertEqual(first.score, first.breakdown.totalScore, accuracy: 0.0001)
    }

    func testTuneSimilarityWeights() {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "결제"),
            .init(id: 3, name: "프론트엔드"),
            .init(id: 4, name: "데이터베이스"),
            .init(id: 5, name: "네이버"),
            .init(id: 6, name: "search"),
            .init(id: 7, name: "로그인"),
            .init(id: 8, name: "회원가입"),
            .init(id: 9, name: "서비스"),
        ]

        let samples: [SimilarityTrainingSample] = [
            .init(query: "검삭", expectedKey: "검색"),
            .init(query: "결재", expectedKey: "결제"),
            .init(query: "vmfhsxmdpsem", expectedKey: "프론트엔드"),
            .init(query: "데이터베스", expectedKey: "데이터베이스"),
            .init(query: "spdlqj", expectedKey: "네이버"),
            .init(query: "ㄴㄷㅁㄱ초", expectedKey: "search"),
            .init(query: "로근인", expectedKey: "로그인"),
            .init(query: "회언가입", expectedKey: "회원가입"),
            .init(query: "서비스", expectedKey: "서비스"),
        ]

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let report = index.tuneSimilarityWeights(
            samples: samples,
            options: .init(maxCandidates: 32, leaderboardSize: 5, seed: 0xA11CE)
        )

        XCTAssertEqual(report.baselineMetrics.sampleCount, samples.count)
        XCTAssertGreaterThan(report.evaluatedCandidates, 0)
        XCTAssertFalse(report.leaderboard.isEmpty)
        XCTAssertGreaterThanOrEqual(report.bestMetrics.top3, report.baselineMetrics.top3)
        XCTAssertGreaterThanOrEqual(report.bestMetrics.mrr, report.baselineMetrics.mrr)

        let reeval = index.evaluateSimilarity(
            samples: samples,
            options: .init(limit: 5, candidateLimitPerVariant: 300, weights: report.bestWeights)
        )
        XCTAssertEqual(reeval.mrr, report.bestMetrics.mrr, accuracy: 0.0001)
        XCTAssertEqual(reeval.top1, report.bestMetrics.top1, accuracy: 0.0001)
    }

    func testDeploymentConfigFileStoreAndABResolve() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("similarity_config.json")
        let store = SimilarityConfigFileStore(fileURL: fileURL)

        let config = SimilarityDeploymentConfig(
            modelVersion: "prod-20260225",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            environments: [
                .development: .init(
                    controlWeights: .default,
                    treatmentWeights: .init(
                        editDistance: 0.5,
                        jaccard: 0.2,
                        keyboard: 0.1,
                        jamo: 0.2,
                        prefixBonus: 0.1,
                        exactBonus: 0.2
                    ),
                    abPolicy: .init(enabled: true, treatmentRatio: 1.0, salt: "dev")
                ),
                .production: .init(
                    controlWeights: .default,
                    treatmentWeights: .init(
                        editDistance: 0.45,
                        jaccard: 0.2,
                        keyboard: 0.15,
                        jamo: 0.2,
                        prefixBonus: 0.08,
                        exactBonus: 0.12
                    ),
                    abPolicy: .init(enabled: true, treatmentRatio: 0.5, salt: "prod-salt")
                ),
            ]
        )

        try store.save(config)
        let loaded = try store.load()
        XCTAssertEqual(loaded.modelVersion, "prod-20260225")
        XCTAssertEqual(loaded.environments[.production]?.abPolicy.enabled, true)

        let resolvedA = try SimilarityWeightsResolver.resolve(
            config: loaded,
            environment: .production,
            userIdentifier: "user-1001"
        )
        let resolvedB = try SimilarityWeightsResolver.resolve(
            config: loaded,
            environment: .production,
            userIdentifier: "user-1001"
        )
        XCTAssertEqual(resolvedA.bucket, resolvedB.bucket)
        XCTAssertEqual(resolvedA.weights, resolvedB.weights)

        let forcedTreatment = try SimilarityWeightsResolver.resolve(
            config: loaded,
            environment: .development,
            userIdentifier: nil,
            forcedBucket: .treatment
        )
        XCTAssertEqual(forcedTreatment.bucket, .treatment)
        XCTAssertNotEqual(forcedTreatment.weights, loaded.environments[.development]?.controlWeights)
    }

    func testFeedbackStoreBoundedAndCompact() async throws {
        let store = SimilarityFeedbackStore(
            options: .init(maxEvents: 4, ttl: 60 * 60 * 24 * 2)
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-(60 * 60 * 24 * 4))

        await store.record(.init(query: "검삭", selectedKey: "검색", timestamp: old, outcome: .clickedResult), now: now)
        await store.record(.init(query: "검삭", selectedKey: "검색", timestamp: now.addingTimeInterval(-10), outcome: .acceptedSuggestion), now: now)
        await store.record(.init(query: "결재", selectedKey: "결제", timestamp: now.addingTimeInterval(-9), outcome: .acceptedSuggestion), now: now)
        await store.record(.init(query: "vmfhsxmdpsem", selectedKey: "프론트엔드", timestamp: now.addingTimeInterval(-8), outcome: .acceptedSuggestion), now: now)
        await store.record(.init(query: "spdlqj", selectedKey: "네이버", timestamp: now.addingTimeInterval(-7), outcome: .clickedResult), now: now)

        let snapshot = await store.snapshot(now: now)
        XCTAssertLessThanOrEqual(snapshot.count, 4)
        XCTAssertFalse(snapshot.contains { $0.timestamp == old })

        let samples = await store.trainingSamples(now: now, maxSamples: 10, minOccurrences: 1)
        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.contains { $0.expectedKey == "검색" })

        let summary = await store.summary(now: now, maxPairs: 10)
        XCTAssertGreaterThan(summary.totalEvents, 0)
        XCTAssertGreaterThanOrEqual(summary.droppedByTTL, 1)

        let summaryData = try await store.summaryJSON(now: now, maxPairs: 10)
        XCTAssertLessThan(summaryData.count, 32_000)
    }

    func testNightlyPipelineUpdatesEnvironmentConfig() throws {
        let items: [Item] = [
            .init(id: 1, name: "검색"),
            .init(id: 2, name: "결제"),
            .init(id: 3, name: "프론트엔드"),
            .init(id: 4, name: "데이터베이스"),
            .init(id: 5, name: "네이버"),
        ]

        let events: [SimilarityQueryEvent] = [
            .init(query: "검삭", selectedKey: "검색", timestamp: Date(timeIntervalSince1970: 1_700_000_001), outcome: .acceptedSuggestion),
            .init(query: "검삭", selectedKey: "검색", timestamp: Date(timeIntervalSince1970: 1_700_000_002), outcome: .acceptedSuggestion),
            .init(query: "결재", selectedKey: "결제", timestamp: Date(timeIntervalSince1970: 1_700_000_003), outcome: .acceptedSuggestion),
            .init(query: "결재", selectedKey: "결제", timestamp: Date(timeIntervalSince1970: 1_700_000_004), outcome: .acceptedSuggestion),
            .init(query: "vmfhsxmdpsem", selectedKey: "프론트엔드", timestamp: Date(timeIntervalSince1970: 1_700_000_005), outcome: .acceptedSuggestion),
            .init(query: "spdlqj", selectedKey: "네이버", timestamp: Date(timeIntervalSince1970: 1_700_000_006), outcome: .clickedResult),
        ]

        let initialConfig = SimilarityDeploymentConfig(
            modelVersion: "prod-1",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            environments: [
                .staging: .init(
                    controlWeights: .default,
                    treatmentWeights: .init(
                        editDistance: 0.30,
                        jaccard: 0.20,
                        keyboard: 0.20,
                        jamo: 0.30,
                        prefixBonus: 0.08,
                        exactBonus: 0.12
                    ),
                    abPolicy: .init(enabled: true, treatmentRatio: 0.5, salt: "staging")
                ),
            ]
        )

        let index = HangulSearchIndex(items: items, keyPath: \.name, policy: .init(indexStrategy: .precompute))
        let tuned = try index.runNightlyTuning(
            feedbackEvents: events,
            deploymentConfig: initialConfig,
            options: .init(environment: .staging, targetBucket: .treatment, maxCandidates: 24, leaderboardSize: 5),
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertGreaterThan(tuned.sampleCount, 0)
        XCTAssertGreaterThanOrEqual(tuned.bestMetrics.mrr, tuned.baselineMetrics.mrr)
        XCTAssertNotEqual(tuned.updatedConfig.modelVersion, initialConfig.modelVersion)
        XCTAssertEqual(tuned.updatedConfig.environments[.staging]?.abPolicy.enabled, true)
        XCTAssertEqual(
            tuned.updatedConfig.environments[.staging]?.treatmentWeights,
            tuned.bestWeights
        )
    }

    func testDeploymentConfigSanitizationAndLoadFallback() throws {
        let dirty = SimilarityDeploymentConfig(
            schemaVersion: 0,
            modelVersion: " ",
            updatedAt: Date(timeIntervalSince1970: 0),
            environments: [
                .staging: .init(
                    controlWeights: .init(
                        editDistance: -10,
                        jaccard: 9,
                        keyboard: -3,
                        jamo: 7,
                        prefixBonus: -1,
                        exactBonus: 4
                    ),
                    treatmentWeights: nil,
                    abPolicy: .init(enabled: true, treatmentRatio: 4.2, salt: " ")
                ),
            ]
        )

        let sanitized = dirty.sanitized()
        XCTAssertEqual(sanitized.schemaVersion, 1)
        XCTAssertFalse(sanitized.modelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(sanitized.environments[.development])
        XCTAssertNotNil(sanitized.environments[.production])

        guard let staging = sanitized.environments[.staging] else {
            XCTFail("Missing staging config after sanitization")
            return
        }

        XCTAssertEqual(staging.abPolicy.enabled, false)
        XCTAssertEqual(staging.abPolicy.treatmentRatio, 0)
        XCTAssertGreaterThan(staging.controlWeights.editDistance, 0)
        XCTAssertLessThanOrEqual(staging.controlWeights.jaccard, 2)
        XCTAssertLessThanOrEqual(staging.controlWeights.exactBonus, 0.5)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("broken_similarity_config.json")
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        let store = SimilarityConfigFileStore(fileURL: fileURL)
        let loaded = store.loadOrDefault()

        XCTAssertNotNil(loaded.environments[.development])
        XCTAssertNotNil(loaded.environments[.production])

        let resolved = SimilarityWeightsResolver.resolveOrDefault(
            config: loaded,
            environment: .production,
            userIdentifier: "user-42"
        )
        XCTAssertEqual(resolved.environment, .production)
        XCTAssertGreaterThan(resolved.weights.editDistance, 0)
    }

    func testSearchTelemetryAndGuardrails() async throws {
        func syncSearch(_ index: HangulSearchIndex<Item>, _ query: String) -> [Item] {
            index.search(query)
        }

        func syncSearchSimilar(_ index: HangulSearchIndex<Item>, _ query: String) -> [ScoredSearchResult<Item>] {
            index.searchSimilar(query, options: .init(limit: 3))
        }

        func syncExplainSimilar(_ index: HangulSearchIndex<Item>, _ query: String) -> [ExplainedSearchResult<Item>] {
            index.explainSimilar(query, options: .init(limit: 1))
        }

        var items: [Item] = []
        items.reserveCapacity(1_200)

        for i in 0..<1_199 {
            items.append(.init(id: i, name: "데이터\(i)"))
        }
        items.append(.init(id: 1_199, name: "프론트엔드"))

        let uncapped = HangulSearchIndex(
            items: items,
            keyPath: \.name,
            policy: .init(indexStrategy: .precompute, cache: .none, maxCandidateScan: nil)
        )
        let capped = HangulSearchIndex(
            items: items,
            keyPath: \.name,
            policy: .init(indexStrategy: .precompute, cache: .lru(capacity: 64), maxCandidateScan: 200)
        )
        let cappedWithShortQuery = HangulSearchIndex(
            items: items,
            keyPath: \.name,
            policy: .init(indexStrategy: .precompute, cache: .none, maxQueryLength: 2, maxCandidateScan: nil)
        )

        XCTAssertEqual(syncSearch(uncapped, "ㅍ").first?.id, 1_199)
        XCTAssertTrue(syncSearch(capped, "ㅍ").isEmpty)

        let shortQueryResult = syncSearch(cappedWithShortQuery, "ㅍㄹ")
        let longQueryResult = syncSearch(cappedWithShortQuery, "ㅍㄹㅌㅇㄷ")
        XCTAssertEqual(longQueryResult.map(\.id), shortQueryResult.map(\.id))

        _ = syncSearch(capped, "ㄷ")
        _ = syncSearch(capped, "ㄷ")

        let cancelledTask = Task { try await capped.search("ㄷ", mode: .contains) }
        cancelledTask.cancel()
        do {
            _ = try await cancelledTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(true)
        }

        _ = syncSearchSimilar(capped, "vmfhsxm")
        _ = try await capped.searchSimilar("vmfhsxm", options: .init(limit: 3))
        _ = syncExplainSimilar(capped, "vmfhsxm")
        _ = try await capped.explainSimilar("vmfhsxm", options: .init(limit: 1))

        let snapshot = capped.telemetrySnapshot()
        XCTAssertGreaterThanOrEqual(snapshot.syncSearchCount, 3)
        XCTAssertGreaterThanOrEqual(snapshot.cacheHitCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.asyncSearchCancelledCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.syncSimilarSearchCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.asyncSimilarSearchSuccessCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.syncExplainCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.asyncExplainSuccessCount, 1)
        XCTAssertGreaterThan(snapshot.meanSyncSearchLatencyMs, 0)

        capped.resetTelemetry()
        let reset = capped.telemetrySnapshot()
        XCTAssertEqual(reset.syncSearchCount, 0)
        XCTAssertEqual(reset.asyncSearchSuccessCount, 0)
        XCTAssertEqual(reset.cacheHitCount, 0)
    }
}
