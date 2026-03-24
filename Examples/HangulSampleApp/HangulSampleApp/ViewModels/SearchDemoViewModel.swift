import Foundation
import Combine
import HangulCore
import HangulSearch

enum SearchStrategyChoice: String, CaseIterable, Identifiable {
    case precompute = "Precompute"
    case lazyCache = "Lazy Cache"
    case ngram = "N-gram(2)"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .precompute:
            return "초성 키를 사전 계산해 검색 지연을 낮춥니다."
        case .lazyCache:
            return "초기 빌드를 줄이고 첫 검색 비용을 분산합니다."
        case .ngram:
            return "후보군을 축소해 대용량에서 안정적인 검색 속도를 노립니다."
        }
    }

    var policy: SearchPolicy {
        switch self {
        case .precompute:
            return SearchPolicy(
                choseongOptions: .init(preserveNonHangul: true, whitespacePolicy: .normalize),
                indexStrategy: .precompute,
                cache: .lru(capacity: 2_048),
                lazyWarmup: .none,
                maxQueryLength: 128,
                maxCandidateScan: nil
            )
        case .lazyCache:
            return SearchPolicy(
                choseongOptions: .init(preserveNonHangul: true, whitespacePolicy: .normalize),
                indexStrategy: .lazyCache,
                cache: .lru(capacity: 2_048),
                lazyWarmup: .background,
                maxQueryLength: 128,
                maxCandidateScan: nil
            )
        case .ngram:
            return SearchPolicy(
                choseongOptions: .init(preserveNonHangul: true, whitespacePolicy: .normalize),
                indexStrategy: .ngram(k: 2),
                cache: .lru(capacity: 2_048),
                lazyWarmup: .none,
                maxQueryLength: 128,
                maxCandidateScan: nil
            )
        }
    }
}

enum MatchModeChoice: String, CaseIterable, Identifiable {
    case contains = "Contains"
    case prefix = "Prefix"
    case exact = "Exact"

    var id: String { rawValue }

    var value: MatchMode {
        switch self {
        case .contains:
            return .contains
        case .prefix:
            return .prefix
        case .exact:
            return .exact
        }
    }
}

enum SimilarityChoice: String, CaseIterable, Identifiable {
    case disabled = "기본 검색만"
    case enabled = "유사도 포함"

    var id: String { rawValue }
}

@MainActor
final class SearchDemoViewModel: ObservableObject {
    @Published var query = ""

    @Published var selectedStrategy: SearchStrategyChoice = .precompute {
        didSet { rebuildIndex() }
    }
    @Published var selectedMode: MatchModeChoice = .contains {
        didSet { scheduleSearch(immediate: true) }
    }
    @Published var similarityChoice: SimilarityChoice = .enabled {
        didSet { scheduleSearch(immediate: true) }
    }
    @Published var debounceMilliseconds: Int = 180
    @Published var maxResults: Int = 20 {
        didSet { scheduleSearch(immediate: true) }
    }
    @Published var minimumSimilarityScore: Double = 0.18 {
        didSet { scheduleSearch(immediate: true) }
    }
    @Published var includeLayoutVariants: Bool = true {
        didSet { scheduleSearch(immediate: true) }
    }

    @Published private(set) var directResults: [SampleKeyword] = []
    @Published private(set) var similarResults: [ScoredSearchResult<SampleKeyword>] = []
    @Published private(set) var isSearching = false
    @Published private(set) var statusMessage = "인덱스 준비 완료"
    @Published private(set) var telemetry: SearchTelemetrySnapshot?

    private var index: HangulSearchIndex<SampleKeyword>
    private var searchTask: Task<Void, Never>?

    init() {
        let initial = HangulSearchIndex(
            items: SampleData.keywords,
            keyPath: \.hangulSearchKey,
            policy: SearchStrategyChoice.precompute.policy
        )
        self.index = initial
        self.telemetry = initial.telemetrySnapshot()
    }

    var settingsSummary: String {
        "\(selectedStrategy.rawValue) | \(selectedMode.rawValue) | \(similarityChoice.rawValue) | debounce \(debounceMilliseconds)ms"
    }

    func onQueryChanged() {
        scheduleSearch(immediate: false)
    }

    func clearQuery() {
        query = ""
        cancelSearch()
        directResults = []
        similarResults = []
        statusMessage = "검색어를 입력해주세요."
        telemetry = index.telemetrySnapshot()
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func scheduleSearch(immediate: Bool) {
        searchTask?.cancel()

        let delayMs = immediate ? 0 : max(0, debounceMilliseconds)
        let delayNs = UInt64(delayMs) * 1_000_000

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if delayNs > 0 {
                    try await Task.sleep(nanoseconds: delayNs)
                }
                try Task.checkCancellation()
                await executeSearch()
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.statusMessage = "검색 오류: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
    }

    private func executeSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            directResults = []
            similarResults = []
            statusMessage = "검색어를 입력해주세요."
            telemetry = index.telemetrySnapshot()
            isSearching = false
            return
        }

        isSearching = true
        statusMessage = "검색 실행 중..."

        let mode = selectedMode.value
        let useSimilarity = similarityChoice == .enabled
        let resultLimit = max(1, maxResults)
        let options = SimilarityOptions(
            limit: resultLimit,
            ngramSize: 2,
            candidateLimitPerVariant: 700,
            includeLayoutVariants: includeLayoutVariants,
            minimumScore: minimumSimilarityScore
        )

        do {
            var found = try await index.search(trimmed, mode: mode)
            if found.count > resultLimit {
                found = Array(found.prefix(resultLimit))
            }

            var scored: [ScoredSearchResult<SampleKeyword>] = []
            if useSimilarity {
                let candidates = try await index.searchSimilar(trimmed, options: options)
                scored = Array(candidates.prefix(resultLimit))
            }

            try Task.checkCancellation()

            directResults = found
            similarResults = scored
            telemetry = index.telemetrySnapshot()
            isSearching = false

            if found.isEmpty && scored.isEmpty {
                statusMessage = "결과가 없습니다."
            } else if scored.isEmpty {
                statusMessage = "직접 매칭 \(found.count)건"
            } else {
                statusMessage = "직접 \(found.count)건 / 유사 \(scored.count)건"
            }
        } catch is CancellationError {
            isSearching = false
        } catch {
            isSearching = false
            statusMessage = "검색 오류: \(error.localizedDescription)"
            telemetry = index.telemetrySnapshot()
        }
    }

    private func rebuildIndex() {
        cancelSearch()

        let started = CFAbsoluteTimeGetCurrent()
        index = HangulSearchIndex(
            items: SampleData.keywords,
            keyPath: \.hangulSearchKey,
            policy: selectedStrategy.policy
        )
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000.0

        directResults = []
        similarResults = []
        telemetry = index.telemetrySnapshot()
        statusMessage = "\(selectedStrategy.rawValue) 인덱스 재구축 \(String(format: "%.1f", elapsedMs))ms"

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleSearch(immediate: true)
        }
    }
}
