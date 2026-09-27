import XCTest
@testable import HangulSearch

final class SearchRegressionTests: XCTestCase {
    func testSearchResultsCrossTaskBoundariesAndKeepRanking() async throws {
        let index = HangulSearchIndex(items: (0..<1_500).map { "네이버\($0)" } + ["네이버", "나이키"], keyPath: \.self)
        let options = SimilarityOptions(limit: 20, includeLayoutVariants: false)
        let sync: (String, SimilarityOptions) -> [ScoredSearchResult<String>] = index.searchSimilar
        let expected = sync("나이버", options)
        let results = try await Task.detached { try await index.searchSimilar("나이버", options: options) }.value
        let explained = try await Task.detached { try await index.explainSimilar("나이버", options: options) }.value
        XCTAssertEqual(results.map(\.item), expected.map(\.item))
        XCTAssertEqual(results.map(\.score), expected.map(\.score))
        XCTAssertEqual(explained.map(\.item), expected.map(\.item))
        XCTAssertEqual(explained.map(\.score), expected.map(\.score))
    }

    func testInvalidMutableOptionsAreSanitizedAtTheBoundary() {
        let index = HangulSearchIndex(items: ["한글"], keyPath: \.self)
        var options = SimilarityOptions(includeLayoutVariants: false)
        options.limit = Int.max
        options.candidateLimitPerVariant = Int.max
        options.ngramSize = Int.max
        options.minimumScore = .nan
        options.weights.editDistance = .infinity
        options.weights.jaccard = .nan
        let results = index.searchSimilar("한글", options: options)
        XCTAssertEqual(results.first?.item, "한글")
        XCTAssertTrue(results.allSatisfy { $0.score.isFinite && (0...1).contains($0.score) })
        let events = [SimilarityQueryEvent(query: "한글", selectedKey: "한글", timestamp: Date(), outcome: .clickedResult)]
        XCTAssertEqual(SimilarityFeedbackStore.trainingSamples(from: events, maxSamples: Int.max).count, 1)
        XCTAssertTrue(SimilarityFeedbackStore.trainingSamples(from: events, maxSamples: -1).isEmpty)
    }

    func testDegenerateTuningWeightsTerminateDeterministically() {
        let index = HangulSearchIndex(items: ["네이버"], keyPath: \.self)
        let options = SimilarityTuningOptions(
            baseWeights: .init(editDistance: 0, jaccard: 0, keyboard: 0, jamo: 0, prefixBonus: 0, exactBonus: 0),
            includeLayoutVariants: false, maxCandidates: 40
        )
        let samples = [SimilarityTrainingSample(query: "나이버", expectedKey: "네이버")]
        let first = index.tuneSimilarityWeights(samples: samples, options: options)
        let second = index.tuneSimilarityWeights(samples: samples, options: options)
        XCTAssertGreaterThan(first.evaluatedCandidates, 1)
        XCTAssertLessThanOrEqual(first.evaluatedCandidates, 40)
        XCTAssertEqual(first.bestWeights, second.bestWeights)
    }

    func testCanonicalChoseongSearchAcrossStrategies() {
        for strategy: IndexStrategy in [.precompute, .lazyCache, .ngram(k: 2), .ngram(k: 3)] {
            let index = HangulSearchIndex(items: ["한글", "한글".decomposedStringWithCanonicalMapping],
                                         keyPath: \.self, policy: .init(indexStrategy: strategy))
            XCTAssertEqual(index.search("ㅎㄱ").count, 2)
            XCTAssertEqual(index.search("\u{1112}\u{1100}").count, 2)
        }
    }

    func testNgramCompactedShortQueryDoesNotLoseMatches() {
        for k in [2, 3] {
            let items = ["가 나", "가나", "다라"]
            let reference = HangulSearchIndex(items: items, keyPath: \.self)
            let index = HangulSearchIndex(items: items, keyPath: \.self, policy: .init(indexStrategy: .ngram(k: k)))
            for query in ["가 ", "가 나", "가나"] {
                for mode: MatchMode in [.contains, .prefix, .exact] {
                    XCTAssertEqual(index.search(query, mode: mode), reference.search(query, mode: mode))
                }
            }
        }
    }

    func testFuzzyRetrievalDoesNotRequireAllNgrams() async throws {
        for strategy: IndexStrategy in [.precompute, .lazyCache, .ngram(k: 2), .ngram(k: 3)] {
            let index = HangulSearchIndex(items: ["프론트엔드", "네이버", "배송조회"],
                                         keyPath: \.self, policy: .init(indexStrategy: strategy))
            let options = SimilarityOptions(includeLayoutVariants: false)
            let syncSearch: (String, SimilarityOptions) -> [ScoredSearchResult<String>] = index.searchSimilar
            XCTAssertEqual(syncSearch("프론드엔드", options).first?.item, "프론트엔드")
            let results = try await index.searchSimilar("프론드엔드", options: options)
            XCTAssertEqual(results.first?.item, "프론트엔드")
        }
    }

    func testExactCandidateSurvivesCandidateLimit() {
        var items: [String] = []
        for a in 0..<21 {
            for b in 0..<21 {
                for c in 0..<21 where items.count < 1_201 {
                    let value = [2 * 588 + a * 28, 11 * 588 + b * 28, 7 * 588 + c * 28]
                        .map { String(UnicodeScalar(0xAC00 + $0)!) }.joined()
                    if value != "네이버" { items.append(value) }
                }
            }
        }
        items.append("네이버")
        let index = HangulSearchIndex(items: items, keyPath: \.self)
        XCTAssertEqual(index.searchSimilar("네이버", options: .init(includeLayoutVariants: false)).first?.item, "네이버")
    }
}
