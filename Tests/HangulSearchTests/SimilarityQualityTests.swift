import XCTest
import HangulCore
@testable import HangulSearch

final class SimilarityQualityTests: XCTestCase {
    func testBoundedTopKMatchesStableFullSort() {
        let values = (0..<500).map { (id: $0, score: ($0 * 37) % 19) }
        for limit in [1, 7, 500] {
            let better: ((id: Int, score: Int), (id: Int, score: Int)) -> Bool = {
                $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
            }
            var heap = BoundedTopK(capacity: limit, isBetter: better)
            for value in values.reversed() { heap.insert(value) }
            XCTAssertEqual(heap.sorted().map(\.id), values.sorted(by: better).prefix(limit).map(\.id))
        }
    }

    func testHoldoutDoesNotLeakNormalizedQueriesIntoTraining() throws {
        let samples: [SimilarityTrainingSample] = [
            .init(query: "한 글", expectedKey: "한글"),
            .init(query: "한글".decomposedStringWithCanonicalMapping, expectedKey: "한글"),
            .init(query: "네이바", expectedKey: "네이버"),
            .init(query: "프론드", expectedKey: "프론트")
        ]
        let split = SimilarityDataset.split(samples)
        let training = Set(split.training.map { SimilarityDataset.queryIdentity($0.query) })
        let validation = Set(split.validation.map { SimilarityDataset.queryIdentity($0.query) })
        XCTAssertTrue(training.isDisjoint(with: validation))
        XCTAssertFalse(validation.isEmpty)
        let index = HangulSearchIndex(items: ["한글", "네이버", "프론트"], keyPath: \.self)
        let report = index.tuneSimilarityWeights(samples: samples, validationSamples: split.validation,
                                                 options: .init(maxCandidates: 8))
        XCTAssertEqual(report.baselineMetrics.sampleCount, split.training.count)
        let control = try XCTUnwrap(report.validationBaselineMetrics)
        let treatment = try XCTUnwrap(report.validationBestMetrics)
        XCTAssertGreaterThanOrEqual(treatment.objectiveScore, control.objectiveScore)
        let fallback = index.tuneSimilarityWeights(samples: split.validation, validationSamples: split.validation,
                                                   options: .init(maxCandidates: 2))
        XCTAssertTrue(fallback.usedValidationFallback)
        XCTAssertEqual(fallback.bestWeights, SimilarityWeights.default)
        let legacy: ([SimilarityTrainingSample], SimilarityTuningOptions) -> SimilarityTuningReport = index.tuneSimilarityWeights
        XCTAssertEqual(legacy(samples, .init(maxCandidates: 1)).evaluatedCandidates, 1)
    }

    func testSyntheticQualityCorpusAcrossStrategies() {
        let pairs = Self.typoPairs
        var cases: [SimilarityEvaluationCase] = []
        for (word, typo) in pairs {
            for query in [word, word.decomposedStringWithCanonicalMapping,
                          word.map(String.init).joined(separator: " "), Hangul.getChoseong(word),
                          Hangul.convertHangulToQwerty(word), typo] {
                cases.append(.init(query: query, relevantKeys: [word]))
            }
        }
        let negatives = ["밥솥", "호랑이", "잠수함", "고래", "연필", "고구마", "치과", "망원경",
                         "양자역학의 비가환 연산자", "바로반영은 안된는", "qzxvqp", "zzqqxx", "🦔🪴", "∑∫∞", "العربية", "%%%%%%%%"]
        cases += negatives.map { .init(query: $0, relevantKeys: []) }
        for strategy: IndexStrategy in [.precompute, .lazyCache, .ngram(k: 2), .ngram(k: 3)] {
            let index = HangulSearchIndex(items: pairs.map(\.0), keyPath: \.self, policy: .init(indexStrategy: strategy))
            for minimum in [0.2, 0.45] {
                let metrics = index.evaluateSimilarity(cases: cases, options: .init(limit: 5, minimumScore: minimum))
                print("[QUALITY] strategy=\(strategy) min=\(minimum) positive=\(metrics.positiveCount) negative=\(metrics.negativeCount) recall@5=\(metrics.recallAtK) precision@5=\(metrics.precisionAtK) mrr=\(metrics.mrr) falsePositiveRate=\(metrics.falsePositiveRate)")
                XCTAssertEqual(metrics.positiveCount, 192)
                XCTAssertEqual(metrics.negativeCount, 16)
                XCTAssertGreaterThanOrEqual(metrics.recallAtK, 0.95)
                XCTAssertGreaterThanOrEqual(metrics.mrr, 0.9)
                if minimum == 0.45 { XCTAssertLessThanOrEqual(metrics.falsePositiveRate, 0.25) }
            }
        }
    }

    private static let typoPairs: [(String, String)] = [
        ("네이버", "나이버"), ("프론트엔드", "프론드엔드"), ("데이터베이스", "데이터베스"), ("검색엔진", "검샥엔진"),
        ("비밀번호", "비밀번로"), ("배송조회", "배숑조회"), ("장바구니", "장바구니ㅣ"), ("환경설정", "환경설졍"),
        ("사용자계정", "사용자게정"), ("알림센터", "알림센타"), ("고객지원", "고겍지원"), ("프로젝트", "프로잭트"),
        ("도서관", "도서괸"), ("고속버스", "고속버수"), ("전기자동차", "전기자동챠"), ("사진앨범", "사진엘범"),
        ("음악재생", "음악제생"), ("영상편집", "영상편짚"), ("문서작성", "문서작셩"), ("일정관리", "일졍관리"),
        ("주소록", "주수록"), ("계산기", "게산기"), ("날씨예보", "날시예보"), ("번역서비스", "번역서비수"),
        ("클라우드", "클라우두"), ("보안인증", "보안인즁"), ("다운로드", "다운로두"), ("업데이트", "업대이트"),
        ("운동기록", "운동기럭"), ("상품리뷰", "샹품리뷰"), ("결제내역", "결재내역"), ("고객상담", "고객샹담")
    ]

    func testDistanceAlgorithmsAndCancellationInsideRows() throws {
        let apple = Array("apple".unicodeScalars)
        let appel = Array("appel".unicodeScalars)
        XCTAssertEqual(StringDistance.distance(apple, appel), 2)
        XCTAssertEqual(StringDistance.distance(apple, appel, algorithm: .optimalStringAlignment), 1)
        var checkpoints = 0
        XCTAssertThrowsError(try StringDistance.distance(
            Array(String(repeating: "가", count: 2_000).unicodeScalars),
            Array(String(repeating: "나", count: 2_000).unicodeScalars),
            cancellationCheck: {
                checkpoints += 1
                if checkpoints == 3 { throw CancellationError() }
            }
        )) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checkpoints, 3)
    }

    func testDistanceMatchesSmallMatrixReference() {
        let tokens = [""] + ["a", "b", "가"] + ["aa", "ab", "ba", "가a", "a가", "aba", "bab"]
        for left in tokens {
            for right in tokens {
                let a = Array(left.unicodeScalars), b = Array(right.unicodeScalars)
                var matrix = (0...a.count).map { i in (0...b.count).map { j in i == 0 ? j : (j == 0 ? i : 0) } }
                for i in a.indices {
                    for j in b.indices {
                        matrix[i + 1][j + 1] = min(matrix[i][j + 1] + 1, matrix[i + 1][j] + 1,
                                                   matrix[i][j] + (a[i] == b[j] ? 0 : 1))
                    }
                }
                XCTAssertEqual(StringDistance.distance(a, b), matrix[a.count][b.count])
                XCTAssertEqual(StringDistance.distance(a, b, algorithm: .optimalStringAlignment),
                               StringDistance.distance(b, a, algorithm: .optimalStringAlignment))
            }
        }
    }

    func testFullWordsDoNotReceiveChoseongOnlyBonuses() {
        let index = HangulSearchIndex(items: ["밥상", "배송조회", "로그인", "비밀번호"], keyPath: \.self)
        let results = index.explainSimilar("밥솥", options: .init(includeLayoutVariants: false))
        XCTAssertEqual(results.first?.item, "밥상")
        XCTAssertFalse(results.contains { $0.item == "배송조회" })
        let choseong = index.searchSimilar("ㅂㅅ", options: .init(includeLayoutVariants: false))
        XCTAssertTrue(choseong.contains { $0.item == "배송조회" })
    }

    func testMixedScriptEvidenceDoesNotDropNonHangul() {
        let index = HangulSearchIndex(items: ["한글ZZZ"], keyPath: \.self)
        let result = index.explainSimilar("한글AAA", options: .init(includeLayoutVariants: false, minimumScore: 0)).first!
        XCTAssertGreaterThan(result.detail.jamoEditDistance, 0)
        XCTAssertTrue(result.detail.jamoQuery.contains("aaa"))
    }

    func testOSAIsOptInAndOldOptionsDecode() throws {
        let index = HangulSearchIndex(items: ["apple"], keyPath: \.self)
        let legacy = index.explainSimilar("appel", options: .init(includeLayoutVariants: false)).first!
        let osa = index.explainSimilar("appel", options: .init(includeLayoutVariants: false, distanceAlgorithm: .optimalStringAlignment)).first!
        XCTAssertEqual(legacy.detail.editDistance, 2)
        XCTAssertEqual(osa.detail.editDistance, 1)
        XCTAssertGreaterThan(osa.score, legacy.score)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SimilarityOptions())) as? [String: Any])
        data.removeValue(forKey: "distanceAlgorithm")
        let decoded = try JSONDecoder().decode(SimilarityOptions.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(decoded.distanceAlgorithm, .levenshtein)
    }
}
